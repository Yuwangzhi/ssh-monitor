import AppKit
import Combine
import SwiftUI
import SSHMonitorCore

@main
struct SSHMonitorMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--probe") {
            guard arguments.indices.contains(index + 1) else {
                fputs("用法：SSHMonitor --probe <SSH 别名>\n", stderr)
                exit(2)
            }
            let host = arguments[index + 1]
            do {
                let snapshot = try RemoteProbe.fetch(host: host)
                print("\(host) CPU \(snapshot.cpuPercent)% MEM \(snapshot.memoryText) GPU max \(snapshot.maxGPUPercent)% (\(snapshot.gpus.count) GPUs)")
                for gpu in snapshot.gpus {
                    print("GPU \(gpu.index): \(gpu.utilization)%  \(gpu.memoryText)  \(gpu.temperatureC)°C")
                }
                exit(0)
            } catch {
                if case SnapshotError.ssh(let detail) = error {
                    fputs("SSH 连接失败：\(detail)\n", stderr)
                } else {
                    fputs("\(error.localizedDescription)\n", stderr)
                }
                exit(1)
            }
        }

        let app = NSApplication.shared
        let delegate = SSHAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class SSHAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = MonitorStore.shared
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "SSH Monitor")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("SSH Monitor，点击查看服务器状态")
        }
        popover.contentSize = NSSize(width: 390, height: 670)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: DashboardView(store: store))
        cancellable = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        store.dismissPanel = { [weak self] in self?.closePopover() }
        updateStatus()
        store.start()

        if CommandLine.arguments.contains("--preview") {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 680),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "SSH Monitor Preview"
            window.contentView = NSHostingView(rootView: DashboardView(store: store))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow = window
        }
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.togglePopover() }
        }
    }

    private func updateStatus() {
        statusItem?.button?.title = ""
        statusItem?.button?.toolTip = store.statusTooltip
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
            installDismissMonitors()
        }
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.closePopover(); return nil }
            } else if let window = event.window,
                      window !== self.popover.contentViewController?.view.window,
                      window !== self.statusItem?.button?.window,
                      window.level < .popUpMenu {
                self.closePopover()
            }
            return event
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        removeDismissMonitors()
    }

    private func removeDismissMonitors() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        outsideMonitor = nil
        localMonitor = nil
    }

    func popoverDidClose(_ notification: Notification) { removeDismissMonitors() }
    func applicationDidResignActive(_ notification: Notification) { closePopover() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePopover() }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { removeDismissMonitors() }
}
