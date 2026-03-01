import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    generalSection
                    servicesSection
                    dataSection
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 520)
    }

    private var generalSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $store.settings.globalNotificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                        Text("Alert when you hit limits")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: store.settings.globalNotificationsEnabled) { _ in store.save() }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom Sound")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                        Text(store.settings.customSoundPath ?? "System default")
                            .font(.system(size: 10))
                            .foregroundColor(store.settings.customSoundPath != nil ? .blue : .secondary)
                    }
                    Spacer()
                    Button("Choose…") { chooseSoundFile() }
                        .font(.system(size: 11))
                    if store.settings.customSoundPath != nil {
                        Button("Reset") {
                            store.settings.customSoundPath = nil
                            store.save()
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    }
                }

                if store.settings.customSoundPath != nil {
                    Button(action: previewSound) {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                            Text("Preview")
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
            .padding(4)
        } label: {
            Text("General")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
    }

    private var servicesSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                ForEach(Array(store.settings.services.enumerated()), id: \.element.name) { index, _ in
                    ServiceConfigRow(
                        config: $store.settings.services[index],
                        store: store
                    )
                    if index < store.settings.services.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(4)
        } label: {
            Text("Platforms")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
    }

    private var dataSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                Button(action: {
                    store.usage = [:]
                    store.saveUsage()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Reset All Usage Data")
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                Text("Clears all tracked usage. Cannot be undone.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(4)
        } label: {
            Text("Data")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
    }

    private func chooseSoundFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.title = "Choose Notification Sound"

        if panel.runModal() == .OK, let url = panel.url {
            let dest = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("UsageBar/Sounds")
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let target = dest.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: url, to: target)
            store.settings.customSoundPath = url.lastPathComponent
            store.save()
        }
    }

    private func previewSound() {
        if let soundName = store.settings.customSoundPath {
            let soundsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("UsageBar/Sounds")
            NSSound(contentsOf: soundsDir.appendingPathComponent(soundName), byReference: true)?.play()
        }
    }
}

struct ServiceConfigRow: View {
    @Binding var config: ServiceConfig
    @ObservedObject var store: UsageStore
    @State private var expanded = false

    var statusDot: Color {
        config.connected ? .green : (config.apiKey.isEmpty && config.trackingMode != .claudeCodeLogs ? .gray : .orange)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Toggle(isOn: $config.enabled) {
                    HStack(spacing: 6) {
                        Text(config.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                        Circle().fill(statusDot).frame(width: 6, height: 6)
                    }
                }
                .onChange(of: config.enabled) { _ in store.save() }

                Spacer()

                Button(action: { withAnimation { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(spacing: 8) {
                    configRow("Tracking") {
                        Picker("", selection: $config.trackingMode) {
                            ForEach(ServiceConfig.TrackingMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .frame(width: 160)
                        .onChange(of: config.trackingMode) { _ in store.save() }
                    }

                    configRow("Daily limit") {
                        TextField("200", value: $config.dailyLimit, format: .number)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: config.dailyLimit) { _ in store.save() }
                    }

                    configRow("Weekly limit") {
                        TextField("1000", value: $config.weeklyLimit, format: .number)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: config.weeklyLimit) { _ in store.save() }
                    }

                    if config.trackingMode != .claudeCodeLogs && config.trackingMode != .manual {
                        configRow("API Key") {
                            SecureField("Enter key...", text: $config.apiKey)
                                .font(.system(size: 11, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: config.apiKey) { _ in store.save() }
                        }
                    }

                    // Connect / Test button
                    HStack {
                        Spacer()
                        Button(action: { store.testConnection(serviceName: config.name) }) {
                            HStack(spacing: 4) {
                                Image(systemName: config.connected ? "checkmark.circle.fill" : "link")
                                    .foregroundColor(config.connected ? .green : .blue)
                                Text(config.connected ? "Connected" : "Test Connection")
                            }
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(config.connected ? .green : .blue)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    private func configRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
        }
    }
}
