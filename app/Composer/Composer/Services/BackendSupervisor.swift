import AppKit
import Foundation

/// Supervises the local Python backend.
///
/// On start, checks whether something is already bound to :5006. If yes,
/// we back off (externallyManaged). Otherwise we spawn
/// `venv/bin/python -m uvicorn backend.server:app --port 5006` from the
/// configured project root, pipe stdout+stderr into a ring buffer, and
/// poll /v1/health until it responds or we give up.
///
/// On app termination we SIGTERM the child and wait up to 2s, then SIGKILL.
final class BackendSupervisor: ObservableObject, @unchecked Sendable {
    enum Status: Equatable {
        case stopped
        case starting
        case running(pid: Int32)
        case externallyManaged
        case failed(String)

        var shortLabel: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting…"
            case .running(let pid): return "Running (pid \(pid))"
            case .externallyManaged: return "External"
            case .failed: return "Failed"
            }
        }
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var recentLog: String = ""

    private var process: Process?
    private let projectRoot: URL
    private let healthURL = URL(string: "http://127.0.0.1:5006/v1/health")!
    private let maxLogChars = 16_000
    private let startupTimeout: TimeInterval = 15

    var projectRootPath: String { projectRoot.path }

    init(projectRoot: URL? = nil) {
        let override = UserDefaults.standard.string(forKey: "COMPOSER_PROJECT_ROOT")
        let path = override ?? projectRoot?.path ?? "/Users/tim/Workspace/composer"
        self.projectRoot = URL(fileURLWithPath: path, isDirectory: true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() async {
        switch status {
        case .starting, .running:
            return
        default:
            break
        }

        await setStatus(.starting)

        if await probeHealthy() {
            await setStatus(.externallyManaged)
            return
        }

        let python = projectRoot.appendingPathComponent("venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            await setStatus(.failed("Python not found at \(python.path). Run `make setup` first."))
            return
        }

        let proc = Process()
        proc.executableURL = python
        proc.currentDirectoryURL = projectRoot
        proc.arguments = ["-m", "uvicorn", "backend.server:app", "--port", "5006"]
        proc.environment = buildEnvironment()

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.appendLog(s) }
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async { self?.handleExit(p) }
        }

        do {
            try proc.run()
        } catch {
            await setStatus(.failed("Spawn failed: \(error.localizedDescription)"))
            return
        }
        process = proc

        let deadline = Date().addingTimeInterval(startupTimeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(300))
            if case .failed = status { return }
            if !proc.isRunning {
                await setStatus(.failed("Backend exited before becoming healthy. See log."))
                return
            }
            if await probeHealthy() {
                await setStatus(.running(pid: proc.processIdentifier))
                return
            }
        }
        await setStatus(.failed("Backend did not become healthy within \(Int(startupTimeout))s."))
    }

    func stop() {
        guard let proc = process, proc.isRunning else {
            Task { await setStatus(.stopped) }
            return
        }
        proc.terminate()
    }

    func restart() {
        Task {
            stop()
            try? await Task.sleep(for: .seconds(1))
            await start()
        }
    }

    @objc private func handleAppTerminate(_ notification: Notification) {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        let deadline = Date().addingTimeInterval(2)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
    }

    @MainActor
    private func setStatus(_ new: Status) {
        status = new
    }

    private func appendLog(_ s: String) {
        recentLog += s
        if recentLog.count > maxLogChars {
            recentLog = String(recentLog.suffix(maxLogChars))
        }
    }

    private func handleExit(_ p: Process) {
        process = nil
        if case .externallyManaged = status { return }
        if case .starting = status { return }  // startup loop will set a better status
        let code = p.terminationStatus
        if code == 0 || code == SIGTERM {
            status = .stopped
        } else {
            status = .failed("Backend exited (code \(code)).")
        }
    }

    private func probeHealthy() async -> Bool {
        var req = URLRequest(url: healthURL)
        req.timeoutInterval = 1.0
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Ensure uvicorn binary in venv is found without explicit path
        let binDir = projectRoot.appendingPathComponent("venv/bin").path
        env["PATH"] = binDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }
}
