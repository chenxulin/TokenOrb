import Foundation

public final class CodexAppServerClient: @unchecked Sendable {
    public typealias SnapshotHandler = (QuotaSnapshot, Bool) -> Void
    public typealias StatusHandler = (String, Bool) -> Void

    public var onSnapshot: SnapshotHandler?
    public var onStatus: StatusHandler?

    private let stateQueue = DispatchQueue(label: "com.tokenorb.app-server")
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var requestIDs = Set<Int>()
    private var nextRequestID = 10
    private var generation = 0
    private var initialized = false

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        stateQueue.async { [weak self] in
            self?.startLocked()
        }
    }

    public func stop() {
        stateQueue.async { [weak self] in
            self?.stopLocked()
        }
    }

    public func stopAndWait() {
        stateQueue.sync {
            stopLocked()
        }
    }

    public func restart() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.stopLocked()
            self.startLocked()
        }
    }

    public func refresh() {
        stateQueue.async { [weak self] in
            self?.requestRefreshLocked()
        }
    }

    private func startLocked() {
        guard process == nil else { return }
        generation += 1
        let activeGeneration = generation
        initialized = false
        requestIDs.removeAll()
        outputBuffer.removeAll(keepingCapacity: true)

        do {
            let executable = try CodexLocator.resolve()
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()

            process.executableURL = executable
            process.arguments = ["app-server"]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors

            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.stateQueue.async {
                    self?.consumeOutputLocked(data, generation: activeGeneration)
                }
            }
            errors.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }
            process.terminationHandler = { [weak self] terminated in
                self?.stateQueue.async {
                    self?.processExitedLocked(terminated, generation: activeGeneration)
                }
            }

            try process.run()
            self.process = process
            inputPipe = input
            outputPipe = output
            errorPipe = errors
            raiseStatus("正在连接 Codex 实时接口…", connected: false)

            sendLocked([
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "token_orb_macos",
                        "title": "Token Orb",
                        "version": "1.3.2",
                    ],
                ],
            ])
        } catch {
            stopLocked()
            raiseStatus(error.localizedDescription, connected: false)
        }
    }

    private func stopLocked() {
        generation += 1
        initialized = false
        requestIDs.removeAll()
        outputBuffer.removeAll(keepingCapacity: false)

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? inputPipe?.fileHandleForWriting.close()

        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }

        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
    }

    private func requestRefreshLocked() {
        guard initialized, process?.isRunning == true else { return }
        nextRequestID += 1
        let requestID = nextRequestID
        requestIDs.insert(requestID)
        sendLocked([
            "method": "account/rateLimits/read",
            "id": requestID,
        ])
    }

    private func sendLocked(_ object: [String: Any]) {
        guard
            let handle = inputPipe?.fileHandleForWriting,
            JSONSerialization.isValidJSONObject(object),
            var data = try? JSONSerialization.data(withJSONObject: object)
        else {
            raiseStatus("Codex 实时接口通信失败", connected: false)
            return
        }

        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
        } catch {
            raiseStatus("Codex 实时接口通信失败：\(error.localizedDescription)", connected: false)
        }
    }

    private func consumeOutputLocked(_ data: Data, generation: Int) {
        guard generation == self.generation else { return }
        outputBuffer.append(data)

        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty, let message = QuotaParser.object(from: Data(line)) else {
                continue
            }
            handleMessageLocked(message)
        }
    }

    private func handleMessageLocked(_ message: [String: Any]) {
        if let id = QuotaParser.int(message["id"]) {
            let result = QuotaParser.dictionary(message["result"])
            let error = QuotaParser.dictionary(message["error"])

            if id == 0, result != nil {
                initialized = true
                sendLocked([
                    "method": "initialized",
                    "params": [:],
                ])
                raiseStatus("实时接口已连接，正在读取额度…", connected: false)
                requestRefreshLocked()
                return
            }

            guard requestIDs.remove(id) != nil else { return }
            if let result,
               let limits = QuotaParser.findRateLimits(in: result),
               let snapshot = QuotaParser.snapshot(
                   fromRateLimits: limits,
                   source: "Codex 实时接口",
                   isLive: true
               ) {
                raiseSnapshot(snapshot, sparse: false)
                raiseStatus("实时同步中", connected: true)
                return
            }

            if let error {
                let message = QuotaParser.string(error["message"]) ?? "未知错误"
                raiseStatus("实时查询失败：\(message)", connected: false)
            } else {
                raiseStatus("实时响应中没有可用额度数据", connected: false)
            }
            return
        }

        guard
            let method = QuotaParser.string(message["method"]),
            method.caseInsensitiveCompare("account/rateLimits/updated") == .orderedSame,
            let parameters = QuotaParser.dictionary(message["params"]),
            let limits = QuotaParser.findRateLimits(in: parameters),
            let snapshot = QuotaParser.snapshot(
                fromRateLimits: limits,
                source: "Codex 实时推送",
                isLive: true
            )
        else {
            return
        }

        raiseSnapshot(snapshot, sparse: true)
        raiseStatus("实时同步中", connected: true)
    }

    private func processExitedLocked(_ terminated: Process, generation: Int) {
        guard generation == self.generation, process === terminated else { return }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        initialized = false
        raiseStatus("Codex 实时接口已断开，使用本地快照", connected: false)
    }

    private func raiseSnapshot(_ snapshot: QuotaSnapshot, sparse: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(snapshot, sparse)
        }
    }

    private func raiseStatus(_ text: String, connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(text, connected)
        }
    }
}
