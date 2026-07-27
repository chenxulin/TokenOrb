import Darwin
import Foundation

public final class CodexAppServerClient: @unchecked Sendable {
    public typealias SnapshotHandler = (QuotaSnapshot, Bool, Int) -> Void
    public typealias StatusHandler = (String, Bool, Int, Bool) -> Void
    public typealias DiagnosticHandler = (String, String) -> Void

    public var onSnapshot: SnapshotHandler?
    public var onStatus: StatusHandler?
    public var onDiagnostic: DiagnosticHandler?

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
    private var retryPolicy = RealtimeRetryPolicy()
    private var retryWorkItem: DispatchWorkItem?
    private var hasSuccessfulLiveQuery = false

    public init() {}

    public var isRunning: Bool {
        stateQueue.sync { process?.isRunning == true }
    }

    public var isInitialized: Bool {
        stateQueue.sync { initialized }
    }

    public var isRecovering: Bool {
        stateQueue.sync { retryPolicy.consecutiveFailures > 0 || retryWorkItem != nil }
    }

    public var currentGeneration: Int {
        stateQueue.sync { generation }
    }

    deinit {
        stop()
    }

    public func start() {
        stateQueue.async { [weak self] in
            self?.restartLocked(preserveRecoveryState: false)
        }
    }

    public func stop() {
        stateQueue.async { [weak self] in
            self?.stopLocked(preserveRecoveryState: false)
        }
    }

    public func stopAndWait() {
        stateQueue.sync {
            stopLocked(preserveRecoveryState: false)
        }
    }

    public func restart() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.restartLocked(preserveRecoveryState: false)
        }
    }

    public func refresh() {
        stateQueue.async { [weak self] in
            self?.requestRefreshLocked()
        }
    }

    private func restartLocked(preserveRecoveryState: Bool) {
        guard stopLocked(preserveRecoveryState: preserveRecoveryState) else {
            handleRealtimeFailureLocked(
                requestID: nil,
                code: "old_process_stop_failed",
                message: "旧 app-server 未能被强制终止。",
                requireInitialized: false,
                operation: "重启实时接口失败"
            )
            return
        }
        startLocked(preserveRecoveryState: preserveRecoveryState)
    }

    private func startLocked(preserveRecoveryState: Bool) {
        guard process == nil else { return }
        generation += 1
        let activeGeneration = generation
        initialized = false
        if !preserveRecoveryState {
            retryPolicy.recordSuccess()
            hasSuccessfulLiveQuery = false
            cancelRetryLocked()
        }
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

            if let error = sendLocked([
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "token_orb_macos",
                        "title": AppIdentity.productName,
                        "version": AppIdentity.protocolVersion,
                    ],
                ],
            ]) {
                raiseDiagnostic("发送 initialize", error.localizedDescription)
                handleRealtimeFailureLocked(
                    requestID: nil,
                    code: "initialize_send_failed",
                    message: error.localizedDescription,
                    requireInitialized: false,
                    operation: "初始化实时接口失败"
                )
            }
        } catch {
            raiseDiagnostic("启动 Codex app-server", error.localizedDescription)
            stopLocked(preserveRecoveryState: true)
            handleRealtimeFailureLocked(
                requestID: nil,
                code: "start_failed",
                message: error.localizedDescription,
                requireInitialized: false,
                operation: "启动实时接口失败"
            )
        }
    }

    @discardableResult
    private func stopLocked(preserveRecoveryState: Bool) -> Bool {
        generation += 1
        initialized = false
        if !preserveRecoveryState {
            retryPolicy.recordSuccess()
            hasSuccessfulLiveQuery = false
            cancelRetryLocked()
        }
        requestIDs.removeAll()
        outputBuffer.removeAll(keepingCapacity: false)

        if let active = process {
            active.terminationHandler = nil
            if active.isRunning {
                let result = Darwin.kill(active.processIdentifier, SIGKILL)
                if result != 0, active.isRunning {
                    let details = String(cString: strerror(errno))
                    raiseDiagnostic("强制终止旧 app-server", details)
                    return false
                }
                active.waitUntilExit()
            }
        }

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? inputPipe?.fileHandleForWriting.close()
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        return true
    }

    private func requestRefreshLocked(cancelScheduledRetry: Bool = true) {
        guard initialized, process?.isRunning == true else { return }
        if cancelScheduledRetry, retryPolicy.consecutiveFailures > 0 {
            return
        }
        guard requestIDs.isEmpty else { return }
        if cancelScheduledRetry {
            cancelRetryLocked()
        }
        nextRequestID += 1
        let requestID = nextRequestID
        requestIDs.insert(requestID)
        if let error = sendLocked([
            "method": "account/rateLimits/read",
            "id": requestID,
        ]) {
            requestIDs.remove(requestID)
            handleQueryFailureLocked(
                requestID: requestID,
                code: "send_failed",
                message: error.localizedDescription
            )
        }
    }

    private func sendLocked(_ object: [String: Any]) -> Error? {
        guard
            let handle = inputPipe?.fileHandleForWriting,
            JSONSerialization.isValidJSONObject(object),
            var data = try? JSONSerialization.data(withJSONObject: object)
        else {
            return ClientError.invalidMessage
        }

        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
            return nil
        } catch {
            return error
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

            if id == 0 {
                guard result != nil else {
                    let message = QuotaParser.string(error?["message"])
                        ?? "Codex 实时接口初始化失败"
                    raiseDiagnostic("初始化 Codex app-server", message)
                    handleRealtimeFailureLocked(
                        requestID: id,
                        code: QuotaParser.string(error?["code"]) ?? "initialize_failed",
                        message: message,
                        requireInitialized: false,
                        operation: "初始化实时接口失败"
                    )
                    return
                }
                initialized = true
                if let sendError = sendLocked([
                    "method": "initialized",
                    "params": [:],
                ]) {
                    raiseDiagnostic("发送 initialized", sendError.localizedDescription)
                    handleRealtimeFailureLocked(
                        requestID: nil,
                        code: "initialized_send_failed",
                        message: sendError.localizedDescription,
                        requireInitialized: false,
                        operation: "初始化实时接口失败"
                    )
                    return
                }
                raiseStatus("实时接口已连接，正在读取额度…", connected: false)
                requestRefreshLocked(cancelScheduledRetry: false)
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
                markQuerySuccessLocked()
                raiseSnapshot(snapshot, sparse: false)
                raiseStatus("实时同步中", connected: true)
                return
            }

            if let error {
                handleQueryFailureLocked(
                    requestID: id,
                    code: QuotaParser.string(error["code"]) ?? "unknown",
                    message: QuotaParser.string(error["message"]) ?? "未提供错误消息。"
                )
            } else {
                handleQueryFailureLocked(
                    requestID: id,
                    code: "missing_rate_limits",
                    message: "实时响应中没有可用额度数据"
                )
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

        markQuerySuccessLocked()
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
        requestIDs.removeAll()
        raiseDiagnostic("Codex app-server 退出", "exitStatus=\(terminated.terminationStatus)")
        handleRealtimeFailureLocked(
            requestID: nil,
            code: "process_exited",
            message: "exitStatus=\(terminated.terminationStatus)",
            requireInitialized: false,
            operation: "Codex app-server 已退出"
        )
    }

    private func markQuerySuccessLocked() {
        retryPolicy.recordSuccess()
        hasSuccessfulLiveQuery = true
        requestIDs.removeAll()
        cancelRetryLocked()
    }

    private func handleQueryFailureLocked(requestID: Int?, code: String, message: String) {
        handleRealtimeFailureLocked(
            requestID: requestID,
            code: code,
            message: message,
            requireInitialized: true,
            operation: "额度查询失败"
        )
    }

    private func handleRealtimeFailureLocked(
        requestID: Int?,
        code: String,
        message: String,
        requireInitialized: Bool,
        operation: String
    ) {
        guard !requireInitialized || initialized else { return }
        // A broken process can report both an RPC/send failure and an exit.
        // Count the current app-server attempt only once.
        guard retryWorkItem == nil else { return }
        let decision = retryPolicy.recordFailure()
        let keepLiveStatus = hasSuccessfulLiveQuery && !decision.useLocalFallback
        scheduleRetryLocked(after: decision.delay)
        let requestText = requestID.map { String($0) } ?? "unknown"
        raiseDiagnostic(
            operation,
            "requestId=\(requestText); code=\(code); consecutiveFailures="
                + "\(retryPolicy.consecutiveFailures); retryDelaySeconds=\(Int(decision.delay)); "
                + "localFallback=\(decision.useLocalFallback); message=\(message)"
        )
        if decision.useLocalFallback {
            let text = retryPolicy.consecutiveFailures == RealtimeRetryPolicy.fallbackFailureThreshold
                ? "实时查询重试 \(RealtimeRetryPolicy.restartRetryCount) 次仍失败，使用本地快照；"
                    + "\(Int(decision.delay)) 秒后重启 app-server 再试"
                : "正在使用本地快照；\(Int(decision.delay)) 秒后重启 app-server 重试实时额度"
            raiseStatus(
                text,
                connected: false,
                useLocalFallback: true
            )
        } else {
            raiseStatus(
                "实时查询失败，\(Int(decision.delay)) 秒后重启 app-server 并重试（"
                    + "\(decision.retryAttempt)/\(RealtimeRetryPolicy.restartRetryCount)）",
                connected: keepLiveStatus
            )
        }
    }

    private func scheduleRetryLocked(after delay: TimeInterval) {
        cancelRetryLocked()
        let activeGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == activeGeneration else { return }
            self.retryWorkItem = nil
            self.restartLocked(preserveRecoveryState: true)
        }
        retryWorkItem = work
        stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelRetryLocked() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
    }

    private func raiseSnapshot(_ snapshot: QuotaSnapshot, sparse: Bool) {
        let sourceGeneration = generation
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(snapshot, sparse, sourceGeneration)
        }
    }

    private func raiseStatus(
        _ text: String,
        connected: Bool,
        useLocalFallback: Bool = false
    ) {
        let sourceGeneration = generation
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(text, connected, sourceGeneration, useLocalFallback)
        }
    }

    private func raiseDiagnostic(_ operation: String, _ details: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onDiagnostic?(operation, details)
        }
    }
}

private enum ClientError: LocalizedError {
    case invalidMessage

    var errorDescription: String? {
        "Codex 实时接口消息无法序列化"
    }
}
