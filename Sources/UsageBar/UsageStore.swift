import Foundation
import UserNotifications
import AppKit

class UsageStore: ObservableObject {
    @Published var settings: AppSettings
    @Published var usage: [String: UsageSnapshot] = [:]
    @Published var lastError: String?

    private let settingsURL: URL
    private let usageURL: URL
    private var notifiedServices: Set<String> = []

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("UsageBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        settingsURL = dir.appendingPathComponent("settings.json")
        usageURL = dir.appendingPathComponent("usage.json")

        // Load settings
        if let data = try? Data(contentsOf: settingsURL),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = s
        } else {
            settings = .default
        }

        // Load cached usage
        if let data = try? Data(contentsOf: usageURL),
           let u = try? JSONDecoder().decode([String: UsageSnapshot].self, from: data) {
            usage = u
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(settings) {
            try? data.write(to: settingsURL)
        }
    }

    func saveUsage() {
        if let data = try? JSONEncoder().encode(usage) {
            try? data.write(to: usageURL)
        }
    }

    func refreshAll() {
        for service in settings.services where service.enabled {
            refreshService(service)
        }
    }

    func refreshService(_ config: ServiceConfig) {
        // Check if we should reset counters
        let now = Date()
        var snap = usage[config.name] ?? .empty

        // Daily reset check
        if now >= snap.dailyResetsAt {
            snap.dailyUsed = 0
            snap.dailyResetsAt = nextDailyReset(hour: config.resetHourUTC)
            snap.limitReached = false
            notifiedServices.remove(config.name)
        }

        // Weekly reset check
        if now >= snap.weeklyResetsAt {
            snap.weeklyUsed = 0
            snap.weeklyResetsAt = nextWeeklyReset()
        }

        // If API key is set, try to fetch real usage
        if !config.apiKey.isEmpty {
            fetchAPIUsage(config: config, snapshot: snap)
        } else {
            snap.lastUpdated = now
            DispatchQueue.main.async {
                self.usage[config.name] = snap
                self.checkLimits(config: config, snapshot: snap)
                self.saveUsage()
            }
        }
    }

    func incrementUsage(service: String, count: Int = 1) {
        guard var snap = usage[service] ?? Optional.some(.empty) else { return }
        snap.dailyUsed += count
        snap.weeklyUsed += count
        snap.lastUpdated = Date()

        if snap.dailyResetsAt < Date() {
            snap.dailyResetsAt = nextDailyReset(hour: 0)
        }
        if snap.weeklyResetsAt < Date() {
            snap.weeklyResetsAt = nextWeeklyReset()
        }

        usage[service] = snap

        if let config = settings.services.first(where: { $0.name == service }) {
            checkLimits(config: config, snapshot: snap)
        }
        saveUsage()
    }

    private func fetchAPIUsage(config: ServiceConfig, snapshot: UsageSnapshot) {
        var snap = snapshot

        switch config.name {
        case "Claude":
            fetchAnthropicUsage(apiKey: config.apiKey) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let count):
                        snap.dailyUsed = count
                        snap.lastUpdated = Date()
                        self?.usage[config.name] = snap
                        self?.checkLimits(config: config, snapshot: snap)
                    case .failure(let err):
                        self?.lastError = err.localizedDescription
                    }
                    self?.saveUsage()
                }
            }
        default:
            // For other services, use local tracking
            snap.lastUpdated = Date()
            DispatchQueue.main.async {
                self.usage[config.name] = snap
                self.saveUsage()
            }
        }
    }

    private func fetchAnthropicUsage(apiKey: String, completion: @escaping (Result<Int, Error>) -> Void) {
        // Anthropic doesn't have a public usage endpoint yet,
        // so we track locally. This is a placeholder for when they add one.
        completion(.success(usage["Claude"]?.dailyUsed ?? 0))
    }

    private func checkLimits(config: ServiceConfig, snapshot: UsageSnapshot) {
        guard settings.globalNotificationsEnabled else { return }
        guard !notifiedServices.contains(config.name) else { return }

        let dailyPct = config.dailyLimit > 0 ? Double(snapshot.dailyUsed) / Double(config.dailyLimit) : 0
        let weeklyPct = config.weeklyLimit > 0 ? Double(snapshot.weeklyUsed) / Double(config.weeklyLimit) : 0

        if dailyPct >= 1.0 || weeklyPct >= 1.0 {
            sendNotification(
                title: "⚠️ \(config.name) Limit Reached",
                body: dailyPct >= 1.0
                    ? "Daily limit of \(config.dailyLimit) reached. Resets \(timeUntil(snapshot.dailyResetsAt))."
                    : "Weekly limit of \(config.weeklyLimit) reached. Resets \(timeUntil(snapshot.weeklyResetsAt)).",
                soundName: config.notificationSound
            )
            notifiedServices.insert(config.name)
            usage[config.name]?.limitReached = true
        } else if dailyPct >= 0.8 || weeklyPct >= 0.8 {
            sendNotification(
                title: "⚡ \(config.name) Usage Warning",
                body: "You've used \(Int(max(dailyPct, weeklyPct) * 100))% of your limit.",
                soundName: config.notificationSound
            )
        }
    }

    private func sendNotification(title: String, body: String, soundName: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if soundName == "default" {
            content.sound = .default
        } else if let customPath = settings.customSoundPath {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: customPath))
        } else {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundName))
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func nextDailyReset(hour: Int) -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC")!
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0
        components.second = 0
        var date = cal.date(from: components)!
        if date <= Date() {
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        return date
    }

    func nextWeeklyReset() -> Date {
        let cal = Calendar.current
        var date = cal.date(byAdding: .day, value: 1, to: Date())!
        while cal.component(.weekday, from: date) != 2 { // Monday
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        return cal.startOfDay(for: date)
    }

    func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSince(Date())
        if interval <= 0 { return "now" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }
}
