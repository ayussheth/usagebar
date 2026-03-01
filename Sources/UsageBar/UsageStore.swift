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
    private var logWatcher: DispatchSourceFileSystemObject?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("UsageBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        settingsURL = dir.appendingPathComponent("settings.json")
        usageURL = dir.appendingPathComponent("usage.json")

        if let data = try? Data(contentsOf: settingsURL),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = s
        } else {
            settings = .default
        }

        if let data = try? Data(contentsOf: usageURL),
           let u = try? JSONDecoder().decode([String: UsageSnapshot].self, from: data) {
            usage = u
        }

        startClaudeCodeWatcher()
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
        let now = Date()
        var snap = usage[config.name] ?? .empty

        if now >= snap.dailyResetsAt {
            snap.dailyUsed = 0
            snap.dailyResetsAt = nextDailyReset(hour: config.resetHourUTC)
            snap.limitReached = false
            notifiedServices.remove(config.name)
        }
        if now >= snap.weeklyResetsAt {
            snap.weeklyUsed = 0
            snap.weeklyResetsAt = nextWeeklyReset()
        }

        switch config.trackingMode {
        case .claudeCodeLogs:
            let stats = readClaudeCodeStats()
            snap.dailyUsed = stats.todayMessages
            snap.weeklyUsed = stats.weekMessages
            snap.detail = "\(stats.todayTokens) tokens today"
            snap.lastUpdated = now
            updateAndCheck(config: config, snap: snap)

        case .anthropicAPI:
            if !config.apiKey.isEmpty {
                fetchAnthropicUsage(apiKey: config.apiKey) { [weak self] count in
                    snap.dailyUsed = count
                    snap.lastUpdated = now
                    self?.updateAndCheck(config: config, snap: snap)
                }
            } else {
                updateAndCheck(config: config, snap: snap)
            }

        case .xaiAPI:
            if !config.apiKey.isEmpty {
                fetchXAIUsage(apiKey: config.apiKey) { [weak self] count in
                    snap.dailyUsed = count
                    snap.lastUpdated = now
                    self?.updateAndCheck(config: config, snap: snap)
                }
            } else {
                updateAndCheck(config: config, snap: snap)
            }

        case .twitterAPI:
            if !config.apiKey.isEmpty {
                fetchTwitterUsage(apiKey: config.apiKey) { [weak self] info in
                    snap.dailyUsed = info.used
                    snap.dailyResetsAt = info.resetsAt
                    snap.detail = "\(info.remaining) remaining"
                    snap.lastUpdated = now
                    self?.updateAndCheck(config: config, snap: snap)
                }
            } else {
                updateAndCheck(config: config, snap: snap)
            }

        case .manual:
            snap.lastUpdated = now
            updateAndCheck(config: config, snap: snap)
        }
    }

    private func updateAndCheck(config: ServiceConfig, snap: UsageSnapshot) {
        DispatchQueue.main.async {
            self.usage[config.name] = snap
            self.checkLimits(config: config, snapshot: snap)
            self.saveUsage()
        }
    }

    // MARK: - Claude Code

    struct ClaudeStats {
        var todayMessages: Int
        var weekMessages: Int
        var todayTokens: Int
    }

    private func readClaudeCodeStats() -> ClaudeStats {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let statsPath = home.appendingPathComponent(".claude/stats-cache.json")

        guard let data = try? Data(contentsOf: statsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dailyActivity = json["dailyActivity"] as? [[String: Any]] else {
            return ClaudeStats(todayMessages: 0, weekMessages: 0, todayTokens: 0)
        }

        let today = dateString(Date())
        let weekAgo = dateString(Calendar.current.date(byAdding: .day, value: -7, to: Date())!)

        var todayMessages = 0
        var weekMessages = 0

        for entry in dailyActivity {
            guard let date = entry["date"] as? String,
                  let count = entry["messageCount"] as? Int else { continue }
            if date == today { todayMessages = count }
            if date >= weekAgo { weekMessages += count }
        }

        var todayTokens = 0
        if let modelTokens = json["dailyModelTokens"] as? [[String: Any]] {
            for entry in modelTokens {
                guard let date = entry["date"] as? String, date == today,
                      let byModel = entry["tokensByModel"] as? [String: Int] else { continue }
                todayTokens = byModel.values.reduce(0, +)
            }
        }

        return ClaudeStats(todayMessages: todayMessages, weekMessages: weekMessages, todayTokens: todayTokens)
    }

    private func startClaudeCodeWatcher() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let statsPath = home.appendingPathComponent(".claude/stats-cache.json").path

        guard FileManager.default.fileExists(atPath: statsPath) else { return }

        let fd = open(statsPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self = self,
                  let config = self.settings.services.first(where: { $0.name == "Claude Code" && $0.enabled }) else { return }
            self.refreshService(config)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        logWatcher = source
    }

    // MARK: - API fetchers

    private func fetchAnthropicUsage(apiKey: String, completion: @escaping (Int) -> Void) {
        let stats = readClaudeCodeStats()
        completion(stats.todayMessages)
    }

    private func fetchXAIUsage(apiKey: String, completion: @escaping (Int) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/api-key")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse,
               let rem = http.value(forHTTPHeaderField: "x-ratelimit-remaining-requests").flatMap({ Int($0) }),
               let lim = http.value(forHTTPHeaderField: "x-ratelimit-limit-requests").flatMap({ Int($0) }) {
                completion(lim - rem)
            } else {
                completion(0)
            }
        }.resume()
    }

    struct TwitterRateInfo {
        var used: Int
        var remaining: Int
        var resetsAt: Date
    }

    private func fetchTwitterUsage(apiKey: String, completion: @escaping (TwitterRateInfo) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.twitter.com/2/usage/tweets")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                let remaining = Int(http.value(forHTTPHeaderField: "x-rate-limit-remaining") ?? "0") ?? 0
                let limit = Int(http.value(forHTTPHeaderField: "x-rate-limit-limit") ?? "0") ?? 0
                let reset = Double(http.value(forHTTPHeaderField: "x-rate-limit-reset") ?? "0") ?? 0
                completion(TwitterRateInfo(used: limit - remaining, remaining: remaining, resetsAt: Date(timeIntervalSince1970: reset)))
            } else {
                completion(TwitterRateInfo(used: 0, remaining: 0, resetsAt: Date()))
            }
        }.resume()
    }

    // MARK: - Usage tracking

    func incrementUsage(service: String, count: Int = 1) {
        var snap = usage[service] ?? .empty
        snap.dailyUsed += count
        snap.weeklyUsed += count
        snap.lastUpdated = Date()
        if snap.dailyResetsAt < Date() { snap.dailyResetsAt = nextDailyReset(hour: 0) }
        if snap.weeklyResetsAt < Date() { snap.weeklyResetsAt = nextWeeklyReset() }
        usage[service] = snap
        if let config = settings.services.first(where: { $0.name == service }) {
            checkLimits(config: config, snapshot: snap)
        }
        saveUsage()
    }

    // MARK: - Notifications

    private func checkLimits(config: ServiceConfig, snapshot: UsageSnapshot) {
        guard settings.globalNotificationsEnabled else { return }
        guard !notifiedServices.contains(config.name) else { return }

        let dailyPct = config.dailyLimit > 0 ? Double(snapshot.dailyUsed) / Double(config.dailyLimit) : 0
        let weeklyPct = config.weeklyLimit > 0 ? Double(snapshot.weeklyUsed) / Double(config.weeklyLimit) : 0

        if dailyPct >= 1.0 || weeklyPct >= 1.0 {
            sendNotification(
                title: "⚠️ \(config.name) Limit Reached",
                body: dailyPct >= 1.0
                    ? "Daily limit of \(config.dailyLimit) hit. Resets \(timeUntil(snapshot.dailyResetsAt))."
                    : "Weekly limit of \(config.weeklyLimit) hit. Resets \(timeUntil(snapshot.weeklyResetsAt)).",
                soundName: config.notificationSound
            )
            notifiedServices.insert(config.name)
            usage[config.name]?.limitReached = true
        } else if dailyPct >= 0.8 || weeklyPct >= 0.8 {
            sendNotification(
                title: "⚡ \(config.name) at \(Int(max(dailyPct, weeklyPct) * 100))%",
                body: "Approaching your usage limit.",
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
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    func nextDailyReset(hour: Int) -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC")!
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        var date = cal.date(from: components)!
        if date <= Date() { date = cal.date(byAdding: .day, value: 1, to: date)! }
        return date
    }

    func nextWeeklyReset() -> Date {
        let cal = Calendar.current
        var date = cal.date(byAdding: .day, value: 1, to: Date())!
        while cal.component(.weekday, from: date) != 2 {
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

    private func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: date)
    }
}
