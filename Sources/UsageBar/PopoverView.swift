import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            serviceListView
            Divider()
            footerView
        }
        .frame(width: 360, height: 540)
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("UsageBar")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                Text(connectedCount)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { showSettings.toggle() }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettings) {
                SettingsView(store: store)
                    .frame(width: 420, height: 520)
            }
            Button(action: { store.refreshAll() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var connectedCount: String {
        let count = store.settings.services.filter { $0.enabled && $0.connected }.count
        let total = store.settings.services.filter { $0.enabled }.count
        return "\(count)/\(total) platforms connected"
    }

    private var serviceListView: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(store.settings.services.filter { $0.enabled }) { service in
                    ServiceRow(
                        config: service,
                        snapshot: store.usage[service.name] ?? .empty,
                        store: store
                    )
                }
                if store.settings.services.filter({ $0.enabled }).isEmpty {
                    emptyView
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No services enabled")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
            Text("Open settings to configure")
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .padding(.top, 40)
    }

    private var footerView: some View {
        HStack {
            if let error = store.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                Text(error)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.orange)
                    .lineLimit(1)
            } else {
                Text("on-device · no cloud")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .font(.system(size: 10, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Service Row

struct ServiceRow: View {
    let config: ServiceConfig
    let snapshot: UsageSnapshot
    @ObservedObject var store: UsageStore

    var dailyPct: Double {
        guard config.dailyLimit > 0 else { return 0 }
        return min(1.0, Double(snapshot.dailyUsed) / Double(config.dailyLimit))
    }

    var weeklyPct: Double {
        guard config.weeklyLimit > 0 else { return 0 }
        return min(1.0, Double(snapshot.weeklyUsed) / Double(config.weeklyLimit))
    }

    var statusColor: Color {
        let pct = max(dailyPct, weeklyPct)
        if pct >= 1.0 { return .red }
        if pct >= 0.8 { return .orange }
        if pct >= 0.5 { return .yellow }
        return .green
    }

    var serviceIcon: String {
        switch config.name {
        case "Claude Code": return "terminal"
        case "Claude API": return "brain.head.profile"
        case "Grok": return "sparkles"
        case "Twitter/X": return "bird"
        case "OpenAI": return "cpu"
        case "Cursor": return "cursorarrow.rays"
        case "Copilot": return "airplane"
        default: return "cpu"
        }
    }

    var connectionIcon: String {
        switch snapshot.status {
        case .connected: return "checkmark.circle.fill"
        case .disconnected: return "circle.dotted"
        case .error: return "exclamationmark.circle.fill"
        case .checking: return "arrow.2.circlepath"
        }
    }

    var connectionColor: Color {
        switch snapshot.status {
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        case .checking: return .orange
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            headerSection
            if config.connected || config.trackingMode == .claudeCodeLogs {
                dailySection
                weeklySection
                detailSection
            } else {
                disconnectedSection
            }
            footerSection
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(snapshot.limitReached ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: serviceIcon)
                .font(.system(size: 12))
                .foregroundColor(statusColor)
                .frame(width: 20)
            Text(config.name)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            Image(systemName: connectionIcon)
                .font(.system(size: 8))
                .foregroundColor(connectionColor)

            Spacer()

            if snapshot.limitReached {
                Text("MAXED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .cornerRadius(3)
            } else {
                Circle().fill(statusColor).frame(width: 6, height: 6)
            }
        }
    }

    private var dailySection: some View {
        VStack(spacing: 3) {
            HStack {
                Text("daily").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
                Text("\(snapshot.dailyUsed)/\(config.dailyLimit)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(dailyPct >= 1.0 ? .red : .primary)
            }
            ProgressView(value: dailyPct)
                .tint(dailyPct >= 1.0 ? .red : dailyPct >= 0.8 ? .orange : .blue)
                .scaleEffect(x: 1, y: 0.6)
        }
    }

    private var weeklySection: some View {
        VStack(spacing: 3) {
            HStack {
                Text("weekly").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
                Text("\(snapshot.weeklyUsed)/\(config.weeklyLimit)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(weeklyPct >= 1.0 ? .red : .primary)
            }
            ProgressView(value: weeklyPct)
                .tint(weeklyPct >= 1.0 ? .red : weeklyPct >= 0.8 ? .orange : .blue)
                .scaleEffect(x: 1, y: 0.6)
        }
    }

    private var detailSection: some View {
        Group {
            if let detail = snapshot.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.blue)
            }
        }
    }

    private var disconnectedSection: some View {
        VStack(spacing: 6) {
            Text(snapshot.detail ?? "Not connected")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            Button(action: { store.testConnection(serviceName: config.name) }) {
                HStack {
                    Image(systemName: "link")
                    Text("Connect")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var footerSection: some View {
        HStack {
            Image(systemName: "clock").font(.system(size: 8)).foregroundColor(.gray)
            Text("resets \(store.timeUntil(snapshot.dailyResetsAt))")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(.gray)
            Spacer()
            if config.trackingMode == .manual {
                Button(action: { store.incrementUsage(service: config.name) }) {
                    Image(systemName: "plus.circle").font(.system(size: 11)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain).help("Log a usage")
            }
            Button(action: { store.testConnection(serviceName: config.name) }) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9)).foregroundColor(.secondary)
            }
            .buttonStyle(.plain).help("Test connection")
        }
    }
}
