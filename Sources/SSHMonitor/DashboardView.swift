import AppKit
import SwiftUI
import SSHMonitorCore

struct DashboardView: View {
    @ObservedObject var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let snapshot = store.snapshot {
                gpuSection(snapshot)
                HStack(spacing: 12) {
                    metric("CPU", value: "\(snapshot.cpuPercent)%", color: .cyan)
                        .frame(width: 106)
                    metric("MEM", value: snapshot.memoryText, color: .orange)
                }
            } else {
                ContentUnavailableView("等待服务器数据", systemImage: "server.rack",
                                       description: Text(store.errorMessage ?? "正在连接服务器…"))
                    .frame(height: 210)
            }
            if store.showSettings { settings }
            controls
        }
        .padding(18)
        .frame(width: 390)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(.cyan)
                Text("SSH Monitor").font(.title2.bold())
                Spacer()
                Circle()
                    .fill(store.isConnected ? Color.green : store.host.isEmpty ? Color.orange : Color.red)
                    .frame(width: 8, height: 8)
                Text(store.isConnected ? "SSH OK" : store.host.isEmpty ? "待配置" : "SSH 离线")
                    .font(.caption.bold())
                    .foregroundStyle(store.isConnected ? .green : store.host.isEmpty ? .orange : .red)
            }
            HStack(spacing: 5) {
                Text("更新于 \(store.lastUpdated?.formatted(date: .omitted, time: .standard) ?? "—")")
                if store.isRefreshing { ProgressView().controlSize(.mini) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if let error = store.navigationError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private func gpuSection(_ snapshot: ServerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("GPU").frame(width: 40, alignment: .leading)
                Text("UTIL").frame(width: 52, alignment: .leading)
                Text("VRAM").frame(maxWidth: .infinity, alignment: .leading)
                Text("TEMP").frame(width: 54, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            if snapshot.gpus.isEmpty {
                Text("GPU 数据不可用")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(snapshot.gpus) { gpu in
                            HStack(spacing: 0) {
                                Text("\(gpu.index)").fontWeight(.bold).frame(width: 40, alignment: .leading)
                                Text("\(gpu.utilization)%")
                                    .foregroundStyle(gpu.utilization >= 80 ? .orange : .cyan)
                                    .fontWeight(.bold)
                                    .frame(width: 52, alignment: .leading)
                                Text(gpu.memoryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(gpu.temperatureC)°C")
                                    .foregroundStyle(gpu.temperatureC >= 85 ? .red : gpu.temperatureC >= 80 ? .orange : .primary)
                                    .fontWeight(gpu.temperatureC >= 80 ? .bold : .regular)
                                    .frame(width: 54, alignment: .trailing)
                            }
                            .font(.system(.callout, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .background(.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
                .frame(height: min(CGFloat(snapshot.gpus.count) * 44, 420))
            }
        }
    }

    private func metric(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(color).fontWeight(.bold)
        }
        .font(.subheadline)
        .monospacedDigit()
        .padding(13)
        .background(.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("SSH 主机别名").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("例如 my-server", text: $store.hostDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveHost)
                Button("保存", action: saveHost)
                    .disabled(!HostValidation.isValid(store.hostDraft))
            }
            Menu {
                ForEach([2, 5, 15, 30, 60], id: \.self) { seconds in
                    Button {
                        store.refreshSeconds = seconds
                    } label: {
                        if store.refreshSeconds == seconds {
                            Label("\(seconds) 秒", systemImage: "checkmark")
                        } else {
                            Text("\(seconds) 秒")
                        }
                    }
                }
            } label: {
                Label("刷新间隔：\(store.refreshSeconds) 秒", systemImage: "timer")
            }
            Text("使用本机 ~/.ssh/config 和 SSH 密钥；采集完成前不会重复连接。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.gray.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                store.refresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing || !HostValidation.isValid(store.host))
            Button {
                store.showSettings.toggle()
                if store.showSettings { store.hostDraft = store.host }
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            Button(action: openSSH) {
                Label("连接 SSH", systemImage: "terminal")
            }
            .disabled(!HostValidation.isValid(store.host))
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("退出 SSH Monitor")
        }
        .buttonStyle(.bordered)
    }

    private func saveHost() {
        let alias = store.hostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HostValidation.isValid(alias) else { return }
        store.host = alias
        store.hostDraft = alias
        store.refresh()
    }

    private func openSSH() {
        guard HostValidation.isValid(store.host),
              let url = URL(string: "ssh://\(store.host)"),
              NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            store.navigationError = "没有可用的 SSH 链接处理程序。"
            return
        }
        if NSWorkspace.shared.open(url) {
            store.navigationError = nil
            store.dismissPanel?()
        } else {
            store.navigationError = "无法打开 SSH 连接。"
        }
    }
}
