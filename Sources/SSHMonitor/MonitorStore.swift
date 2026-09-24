import Foundation
import SSHMonitorCore

@MainActor
final class MonitorStore: ObservableObject {
    static let shared = MonitorStore()

    @Published var host: String {
        didSet {
            UserDefaults.standard.set(host, forKey: "sshHost")
            snapshot = nil
            lastUpdated = nil
            errorMessage = nil
        }
    }
    @Published var refreshSeconds: Int {
        didSet {
            UserDefaults.standard.set(refreshSeconds, forKey: "refreshSeconds")
            if started { scheduleTimer() }
        }
    }
    @Published private(set) var snapshot: ServerSnapshot?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published var showSettings = false
    @Published var hostDraft: String
    @Published var navigationError: String?

    var dismissPanel: (() -> Void)?

    private var timer: Timer?
    private var started = false

    private init() {
        let savedHost = UserDefaults.standard.string(forKey: "sshHost") ?? ""
        host = savedHost
        hostDraft = savedHost
        let savedInterval = UserDefaults.standard.integer(forKey: "refreshSeconds")
        refreshSeconds = [2, 5, 15, 30, 60].contains(savedInterval) ? savedInterval : 2
        showSettings = savedHost.isEmpty
    }

    var isConnected: Bool { snapshot != nil && errorMessage == nil }

    var menuTitle: String {
        if host.isEmpty { return "SSH Monitor" }
        guard isConnected, let snapshot else { return "SSH 离线" }
        return snapshot.gpus.isEmpty ? "SSH OK" : "SSH GPU \(snapshot.maxGPUPercent)%"
    }

    var statusTooltip: String {
        if host.isEmpty { return "SSH Monitor · 请配置 SSH 主机别名" }
        guard isConnected, let snapshot else { return "SSH 离线" }
        return "GPU 最高 \(snapshot.maxGPUPercent)% · CPU \(snapshot.cpuPercent)% · 内存 \(snapshot.memoryText)"
    }

    func start() {
        guard !started else { return }
        started = true
        scheduleTimer()
        refresh()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        guard HostValidation.isValid(host) else {
            errorMessage = "请在设置中填写 ~/.ssh/config 的主机别名。"
            return
        }
        isRefreshing = true
        let currentHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        Task.detached(priority: .utility) { [self] in
            let result = Result { try RemoteProbe.fetch(host: currentHost) }
            await self.finish(result, for: currentHost)
        }
    }

    private func finish(_ result: Result<ServerSnapshot, Error>, for checkedHost: String) {
        isRefreshing = false
        if checkedHost != host {
            refresh()
            return
        }
        switch result {
        case .success(let newSnapshot):
            snapshot = newSnapshot
            lastUpdated = Date()
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
