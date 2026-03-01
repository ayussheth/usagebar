import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @State private var selectedService: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
                    // Global settings
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $store.settings.globalNotificationsEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Notifications")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    Text("Get alerted when you hit limits")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .onChange(of: store.settings.globalNotificationsEnabled) { _ in store.save() }

                            Divider()

                            // Custom sound
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Custom Sound")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    if let path = store.settings.customSoundPath {
                                        Text(URL(fileURLWithPath: path).lastPathComponent)
                                            .font(.system(size: 10))
                                            .foregroundColor(.blue)
                                    } else {
                                        Text("Using system default")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Choose…") {
                                    chooseSoundFile()
                                }
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

                            // Preview sound
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

                    // Services
                    GroupBox {
                        VStack(spacing: 8) {
                            ForEach(Array(store.settings.services.enumerated()), id: \.element.name) { index, service in
                                ServiceConfigRow(
                                    config: $store.settings.services[index],
                                    onSave: { store.save() }
                                )
                                if index < store.settings.services.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding(4)
                    } label: {
                        Text("Services")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }

                    // Reset usage
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

                            Text("This clears all tracked usage counters. Cannot be undone.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    } label: {
                        Text("Data")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 400, height: 500)
    }

    private func chooseSoundFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Notification Sound"
        panel.message = "Select an .aiff, .wav, or .mp3 file"

        if panel.runModal() == .OK, let url = panel.url {
            // Copy to app support for persistence
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
            let soundURL = soundsDir.appendingPathComponent(soundName)
            NSSound(contentsOf: soundURL, byReference: true)?.play()
        }
    }
}

struct ServiceConfigRow: View {
    @Binding var config: ServiceConfig
    let onSave: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Toggle(isOn: $config.enabled) {
                    Text(config.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .onChange(of: config.enabled) { _ in onSave() }

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
                    HStack {
                        Text("Daily limit")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        TextField("100", value: $config.dailyLimit, format: .number)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: config.dailyLimit) { _ in onSave() }
                    }
                    HStack {
                        Text("Weekly limit")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        TextField("500", value: $config.weeklyLimit, format: .number)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: config.weeklyLimit) { _ in onSave() }
                    }
                    HStack {
                        Text("API Key")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        SecureField("optional", text: $config.apiKey)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: config.apiKey) { _ in onSave() }
                    }
                    HStack {
                        Text("Tracking")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Picker("", selection: $config.trackingMode) {
                            ForEach(ServiceConfig.TrackingMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .frame(width: 150)
                        .onChange(of: config.trackingMode) { _ in onSave() }
                    }
                    HStack {
                        Text("Reset hour")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Picker("", selection: $config.resetHourUTC) {
                            ForEach(0..<24, id: \.self) { h in
                                Text("\(h):00 UTC").tag(h)
                            }
                        }
                        .frame(width: 100)
                        .onChange(of: config.resetHourUTC) { _ in onSave() }
                    }
                }
                .padding(.leading, 20)
            }
        }
    }
}
