using System;
using System.IO;
using System.Threading;
using System.Windows.Threading;

namespace CodexQuotaBall
{
    public sealed class QuotaService : IDisposable
    {
        private readonly Dispatcher dispatcher;
        private readonly bool demoMode;
        private readonly SessionQuotaReader sessionReader;
        private readonly CodexAppServerClient appServer;
        private readonly DispatcherTimer localDebounceTimer;
        private readonly DispatcherTimer localPollTimer;
        private readonly DispatcherTimer rpcRefreshTimer;
        private readonly DispatcherTimer rpcRetryTimer;
        private FileSystemWatcher watcher;
        private QuotaSnapshot currentSnapshot;
        private QuotaSnapshot liveSnapshot;
        private bool liveConnected;
        private bool disposed;

        public event Action<QuotaSnapshot> SnapshotChanged;
        public event Action<string, bool> ConnectionChanged;

        public QuotaService(Dispatcher dispatcher, bool demoMode)
        {
            this.dispatcher = dispatcher;
            this.demoMode = demoMode;
            sessionReader = new SessionQuotaReader(SessionQuotaReader.FindSessionsRoot());
            appServer = new CodexAppServerClient();
            appServer.SnapshotReceived += OnRpcSnapshot;
            appServer.StatusChanged += OnRpcStatus;

            localDebounceTimer = new DispatcherTimer(DispatcherPriority.Background, dispatcher);
            localDebounceTimer.Interval = TimeSpan.FromMilliseconds(650);
            localDebounceTimer.Tick += delegate
            {
                localDebounceTimer.Stop();
                RefreshLocal();
            };

            localPollTimer = new DispatcherTimer(DispatcherPriority.Background, dispatcher);
            localPollTimer.Interval = TimeSpan.FromSeconds(20);
            localPollTimer.Tick += delegate { RefreshLocal(); };

            rpcRefreshTimer = new DispatcherTimer(DispatcherPriority.Background, dispatcher);
            rpcRefreshTimer.Interval = TimeSpan.FromSeconds(30);
            rpcRefreshTimer.Tick += delegate { appServer.RequestRefresh(); };

            rpcRetryTimer = new DispatcherTimer(DispatcherPriority.Background, dispatcher);
            rpcRetryTimer.Interval = TimeSpan.FromMinutes(2);
            rpcRetryTimer.Tick += delegate
            {
                RunAppServerBackground(delegate
                {
                    if (!appServer.IsRunning || !appServer.IsInitialized)
                    {
                        appServer.Restart();
                    }
                });
            };
        }

        public QuotaSnapshot CurrentSnapshot
        {
            get { return currentSnapshot; }
        }

        public void Start()
        {
            if (demoMode)
            {
                currentSnapshot = CreateDemoSnapshot();
                RaiseSnapshot(currentSnapshot);
                RaiseConnection("演示数据", true);
                return;
            }

            RefreshLocal();
            StartWatcher();
            localPollTimer.Start();
            rpcRefreshTimer.Start();
            rpcRetryTimer.Start();
            RaiseConnection("正在准备 Codex 实时接口…", false);
            RunAppServerBackground(appServer.Start);
        }

        public void ManualRefresh()
        {
            if (demoMode)
            {
                currentSnapshot = CreateDemoSnapshot();
                RaiseSnapshot(currentSnapshot);
                return;
            }

            RefreshLocal();
            RaiseConnection("正在刷新实时额度…", false);
            RunAppServerBackground(delegate
            {
                if (appServer.IsRunning)
                {
                    appServer.RequestRefresh();
                }
                else
                {
                    appServer.Restart();
                }
            });
        }

        private void RunAppServerBackground(Action action)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                if (disposed)
                {
                    return;
                }
                try
                {
                    action();
                }
                catch
                {
                    OnRpcStatus("实时接口不可用，使用本地快照", false);
                }
            });
        }

        private void StartWatcher()
        {
            try
            {
                if (!Directory.Exists(sessionReader.SessionsRoot))
                {
                    return;
                }

                watcher = new FileSystemWatcher(sessionReader.SessionsRoot, "*.jsonl");
                watcher.IncludeSubdirectories = true;
                watcher.NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size;
                watcher.Changed += OnSessionFileChanged;
                watcher.Created += OnSessionFileChanged;
                watcher.Renamed += OnSessionFileRenamed;
                watcher.EnableRaisingEvents = true;
            }
            catch
            {
                watcher = null;
            }
        }

        private void OnSessionFileChanged(object sender, FileSystemEventArgs args)
        {
            ScheduleLocalRefresh();
        }

        private void OnSessionFileRenamed(object sender, RenamedEventArgs args)
        {
            ScheduleLocalRefresh();
        }

        private void ScheduleLocalRefresh()
        {
            if (disposed)
            {
                return;
            }

            dispatcher.BeginInvoke(new Action(delegate
            {
                if (disposed)
                {
                    return;
                }
                localDebounceTimer.Stop();
                localDebounceTimer.Start();
            }));
        }

        private void RefreshLocal()
        {
            if (disposed || demoMode)
            {
                return;
            }

            QuotaSnapshot local = sessionReader.LoadLatest();
            if (local == null || !local.HasQuotaData)
            {
                if (currentSnapshot == null)
                {
                    RaiseConnection("等待 Codex 产生额度数据…", false);
                }
                return;
            }

            if (!liveConnected)
            {
                bool changed = currentSnapshot == null
                    || currentSnapshot.IsLive
                    || local.CapturedAt > currentSnapshot.CapturedAt;
                currentSnapshot = local;
                if (changed)
                {
                    RaiseSnapshot(currentSnapshot);
                }
            }
        }

        private void OnRpcSnapshot(QuotaSnapshot snapshot, bool sparse)
        {
            dispatcher.BeginInvoke(new Action(delegate
            {
                if (disposed || snapshot == null)
                {
                    return;
                }

                liveSnapshot = sparse && liveSnapshot != null
                    ? liveSnapshot.MergeSparse(snapshot)
                    : snapshot;
                liveSnapshot.IsLive = true;
                currentSnapshot = liveSnapshot;
                liveConnected = true;
                RaiseSnapshot(currentSnapshot);
            }));
        }

        private void OnRpcStatus(string text, bool connected)
        {
            dispatcher.BeginInvoke(new Action(delegate
            {
                if (disposed)
                {
                    return;
                }

                liveConnected = connected;
                RaiseConnection(text, connected);
                if (!connected)
                {
                    RefreshLocal();
                }
            }));
        }

        private void RaiseSnapshot(QuotaSnapshot snapshot)
        {
            Action<QuotaSnapshot> handler = SnapshotChanged;
            if (handler != null)
            {
                handler(snapshot);
            }
        }

        private void RaiseConnection(string text, bool connected)
        {
            Action<string, bool> handler = ConnectionChanged;
            if (handler != null)
            {
                handler(text, connected);
            }
        }

        private static QuotaSnapshot CreateDemoSnapshot()
        {
            long now = Convert.ToInt64((DateTimeOffset.UtcNow - new DateTimeOffset(1970, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds);
            return new QuotaSnapshot
            {
                LimitId = "codex",
                Primary = new QuotaWindowInfo
                {
                    UsedPercent = 31.0,
                    WindowMinutes = 300,
                    ResetsAtUnix = now + 2 * 3600 + 27 * 60
                },
                Secondary = new QuotaWindowInfo
                {
                    UsedPercent = 54.0,
                    WindowMinutes = 10080,
                    ResetsAtUnix = now + 4 * 86400 + 7 * 3600
                },
                Credits = new QuotaCreditsInfo
                {
                    HasCredits = true,
                    Unlimited = false,
                    Balance = "2226.6674375000"
                },
                PlanType = "plus",
                CapturedAt = DateTimeOffset.Now,
                Source = "演示数据",
                IsLive = true
            };
        }

        public void Dispose()
        {
            if (disposed)
            {
                return;
            }
            disposed = true;

            localDebounceTimer.Stop();
            localPollTimer.Stop();
            rpcRefreshTimer.Stop();
            rpcRetryTimer.Stop();

            if (watcher != null)
            {
                try
                {
                    watcher.EnableRaisingEvents = false;
                    watcher.Changed -= OnSessionFileChanged;
                    watcher.Created -= OnSessionFileChanged;
                    watcher.Renamed -= OnSessionFileRenamed;
                    watcher.Dispose();
                }
                catch { }
                watcher = null;
            }

            appServer.SnapshotReceived -= OnRpcSnapshot;
            appServer.StatusChanged -= OnRpcStatus;
            appServer.Dispose();
        }
    }
}
