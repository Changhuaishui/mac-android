import SwiftUI
import MacHostKit

enum ServiceStatus: String {
    case stopped = "已停止"
    case listening = "监听中"
    case connected = "已连接"
}

@main
struct MacHostApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 560, minHeight: 420)
        }
        .defaultSize(width: 560, height: 420)
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = MacHostViewModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeaderView(viewModel: viewModel)
            ProfileInfoView(viewModel: viewModel)
            StatsView(viewModel: viewModel)
            LogView(logs: viewModel.logs)
            Spacer()
            HStack {
                Spacer()
                Button(action: { viewModel.toggleService() }) {
                    Text(viewModel.isRunning ? "停止服务" : "启动服务")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
    }
}

struct HeaderView: View {
    @ObservedObject var viewModel: MacHostViewModel
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mac Host").font(.title).fontWeight(.semibold)
                Text(viewModel.configSummary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: viewModel.status)
        }
    }
}

struct ProfileInfoView: View {
    @ObservedObject var viewModel: MacHostViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("档位与输出").font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Android 当前模式:").font(.caption).foregroundStyle(.secondary)
                    Text(viewModel.currentMode).font(.caption).fontWeight(.medium)
                }
                HStack {
                    Text("已选 profile:").font(.caption).foregroundStyle(.secondary)
                    Text(viewModel.selectedProfile).font(.caption).fontWeight(.medium)
                }
                HStack {
                    Text("实际输出:").font(.caption).foregroundStyle(.secondary)
                    Text(viewModel.outputSummary).font(.caption).fontWeight(.medium)
                }
                if !viewModel.degradationReason.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(viewModel.degradationReason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct StatusBadge: View {
    let status: ServiceStatus
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(status.rawValue).font(.callout).fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    var color: Color {
        switch status {
        case .stopped: return .gray
        case .listening: return .orange
        case .connected: return .green
        }
    }
}

struct StatsView: View {
    @ObservedObject var viewModel: MacHostViewModel
    var body: some View {
        HStack(spacing: 16) {
            StatItem(title: "FPS", value: viewModel.fps)
            StatItem(title: "码率", value: viewModel.bitrate)
            StatItem(title: "编码耗时", value: viewModel.encodeTime)
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).fontWeight(.medium).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LogView: View {
    let logs: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("日志").font(.caption).foregroundStyle(.secondary)
            List(logs, id: \.self) { log in
                Text(log)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .listStyle(.plain)
            .frame(height: 120)
            .border(Color.secondary.opacity(0.2))
        }
    }
}

@MainActor
final class MacHostViewModel: ObservableObject {
    @Published var status: ServiceStatus = .stopped
    @Published var isRunning = false
    @Published var fps = "-"
    @Published var bitrate = "-"
    @Published var encodeTime = "-"
    @Published var configSummary = ""
    @Published var currentMode = "-"
    @Published var selectedProfile = "-"
    @Published var outputSummary = "-"
    @Published var degradationReason = ""
    @Published var logs: [String] = []
    private var host: MacHost?
    private let maxLogLines = 100
    /// App 默认使用 balanced 档；如需切换可在后续版本加选择器。
    private let appProfile: Profile = .balanced

    init() {
        let config = Configuration()
        configSummary = "\(config.width)x\(config.height) @ \(Int(config.fps))fps, \(config.bitrate / 1_000_000) Mbps, port \(config.port)"
    }

    func toggleService() {
        if isRunning {
            stopService()
        } else {
            startService()
        }
    }

    private func startService() {
        var config = Configuration()
        config.profile = appProfile
        let host = MacHost(configuration: config)
        self.host = host
        host.statusDelegate = self
        host.setLoggerDelegate(self)
        Task {
            let started = await host.start()
            if !started {
                self.appendLog("启动失败")
                self.host = nil
            }
        }
    }

    private func stopService() {
        host?.stop()
    }

    private func appendLog(_ message: String) {
        logs.append(message)
        if logs.count > maxLogLines {
            logs.removeFirst(logs.count - maxLogLines)
        }
    }
}

extension MacHostViewModel: MacHostStatusDelegate {
    nonisolated func hostDidStartListening(_ host: MacHost) {
        Task { @MainActor in
            self.status = .listening
            self.isRunning = true
        }
    }

    nonisolated func hostDidReceiveHello(_ host: MacHost, capabilities: DisplayCapabilities?) {
        Task { @MainActor in
            if let mode = capabilities?.currentMode {
                self.currentMode = mode.summary
            } else {
                self.currentMode = "未上报"
            }
        }
    }

    nonisolated func hostDidSelectProfile(_ host: MacHost, profile: Profile, output: StreamConfiguration) {
        Task { @MainActor in
            self.selectedProfile = profile.description
            self.outputSummary = output.summary
            self.degradationReason = output.degradationReason ?? ""
        }
    }

    nonisolated func hostDidAcceptConnection(_ host: MacHost) {
        Task { @MainActor in
            self.status = .connected
        }
    }

    nonisolated func hostDidLoseConnection(_ host: MacHost, error: Error?) {
        Task { @MainActor in
            self.status = .listening
        }
    }

    nonisolated func hostDidStop(_ host: MacHost) {
        Task { @MainActor in
            self.status = .stopped
            self.isRunning = false
            if self.host === host {
                self.host = nil
            }
        }
    }
}

extension MacHostViewModel: LoggerDelegate {
    nonisolated func loggerDidOutputMessage(_ message: String, isError: Bool) {
        Task { @MainActor in
            self.appendLog(message)
        }
    }

    nonisolated func loggerDidOutputStats(fps: Double, bitrateMbps: Double, avgEncodeMs: Double) {
        Task { @MainActor in
            self.fps = String(format: "%.1f", fps)
            self.bitrate = String(format: "%.2f Mbps", bitrateMbps)
            self.encodeTime = String(format: "%.2f ms", avgEncodeMs)
        }
    }
}
