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

        // Try loading settings, fall back to defaults
        if let data = try? Data(contentsOf: settingsURL),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = s
        } else {
            settings = .default
            // Delete old format settings
            try? FileManager.default.removeItem(at: settingsURL)
        }

        if let data = try? Data(contentsOf: usageURL),
           let u = try? JSONDecoder().decode([String: UsageSnapshot].self, from: data) {
            usage = u
        }

        save()
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

    func testConnection(serviceName: String) {
        guard let idx = settings.services.firstIndex(where: { $0.name == serviceName }) else { return }
        var snap = usage[serviceName] ?? .empty
        snap.status = .checking
        usage[serviceName] = snap

        let config = settings.services[idx]

        switch config.trackingMode {
        case .claudeCodeLogs:
            let home = FileManager.default.homeDirectoryForCurrentUser
            let statsPath = home.appendingPathComponent(".claude/stats-cache.json")
            if FileManager.default.fileExists(atPath: statsPath.path) {
                settings.services[idx].connected = true
                snap.status = .connected
                snap.detail = "Reading ~/.claude/stats-cache.json"
            } else {
                settings.services[idx].connected = false
                snap.status = .error
                snap.detail = "~/.claude/stats-cache.json not found"
            }
            usage[serviceName] = snap
            save()

        case .anthropicAPI:
            guard !config.apiKey.isEmpty else {
                snap.status = .disconnected
                snap.detail = "Add API key to connect"
                usage[serviceName] = snap
                return
            }
            testAnthropicKey(apiKey: config.apiKey) { [weak self] ok, msg in
                DispatchQueue.main.async {
                    self?.settings.services[idx].connected = ok
                    snap.status = ok ? .connected : .error
                    snap.detail = msg
                    self?.usage[serviceName] = snap
                    self?.save()
                }
            }

        case .xaiAPI:
            guard !config.apiKey.isEmpty else {
                snap.status = .disconnected
                snap.detail = "Add API key to connect"
                usage[serviceName] = snap
                return
            }
            testXAIKey(apiKey: config.apiKey) { [weak self] ok, msg in
                DispatchQueue.main.async {
                    self?.settings.services[idx].connected = ok
                    snap.status = ok ? .connected : .error
                    snap.detail = msg
                    self?.usage[serviceName] = snap
                    self?.save()
                }
            }

        case .twitterAPI:
            guard !config.apiKey.isEmpty else {
                snap.status = .disconnected
                snap.detail = "Add Bearer token to connect"
                usage[serviceName] = snap
                return
            }
            testTwitterKey(apiKey: config.apiKey) { [weak self] ok, msg in
                DispatchQueue.main.async {
                    self?.settings.services[idx].connected = ok
                    snap.status = ok ? .connected : .error
                    snap.detail = msg
                    self?.usage[serviceName] = snap
                    self?.save()
                }
            }

        case .openaiAPI:
            guard !config.apiKey.isEmpty else {
                snap.status = .disconnected
                snap.detail = "Add API key to connect"
                usage[serviceName] = snap
                return
            }
            testOpenAIKey(apiKey: config.apiKey) { [weak self] ok, msg in
                DispatchQueue.main.async {
                    self?.settings.services[idx].connected = ok
                    snap.status = ok ? .connected : .error
                    snap.detail = msg
                    self?.usage[serviceName] = snap
                    self?.save()
                }
            }

        case .manual:
            settings.services[idx].connected = true
            snap.status = .connected
            snap.detail = "Manual tracking"
            usage[serviceName] = snap
            save()
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
            snap.detail = "\(stats.todayTokens) tokens · \(stats.todaySessions) sessions today"
            snap.status = .connected
            snap.lastUpdated = now
            updateAndCheck(config: config, snap: snap)

        case .anthropicAPI:
            if !config.apiKey.isEmpty {
                fetchAnthropicUsage(apiKey: config.apiKey) { [weak self] daily, detail in
                    snap.dailyUsed = daily
                    snap.detail = detail
                    snap.status = .connected
                    snap.lastUpdated = now
                    self?.updateAndCheck(config: config, snap: snap)
                }
            } else {
                snap.status = .disconnected
                snap.detail = "Add API key"
                updateAndCheck(config: config, snap: snap)
            }

        case .xaiAPI:
            if !config.apiKey.isEmpty {
                fetchXAIUsage(apiKey: config.apiKey) { [weak self] used, remaining, detail in
                    snap.dailyUsed = used
                    snap.detail = detail
                    snap.status = .connected
                    snap.lastUpdated = now
                    self?.updateAndCheck(config: config, snap: snap)
                }
            } else {
                snap.status = .disconnected
                updateAndCheck(config: config, snap: snap)
            }

        case .twitterAPI:
            if !config.apiKey.isEmpty {
                fetchTwitterUsage(apiKey: config.apiKey) { [weak self] info in
                    snap.dailyUsed = info.used
                    snap.dailyResetsAt = info.resetsAt
                    snap.detail = "\(info.remaining) calls remaining"
                    snap.status = .connected
                    snap.lastUpdated = now
                    self?.updateAndCheck(config: config, snap: snap)
                }
            } else {
                snap.status = .disconnected
                updateAndCheck(config: config, snap: snap)
            }

        case .openaiAPI:
            if !config.apiKey.isEmpty {
                fetchOpenAIUsage(apiKey: config.apiKey) { [weak self] used, detail in
                    snap.dailyUsed = used
                    snap.detail = detail
                    snap.status = .connected
                    snap.lastUpdated = now
                    self?.updateAndCheck(config: config, snap: snap)
                }
            } else {
                snap.status = .disconnected
                updateAndCheck(config: config, snap: snap)
            }

        case .manual:
            snap.lastUpdated = now
            snap.status = .connected
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

    // MARK: - Claude Code local stats

    struct ClaudeStats {
        var todayMessages: Int
        var weekMessages: Int
        var todayTokens: Int
        var todaySessions: Int
    }

    private func readClaudeCodeStats() -> ClaudeStats {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let statsPath = home.appendingPathComponent(".claude/stats-cache.json")

        guard let data = try? Data(contentsOf: statsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dailyActivity = json["dailyActivity"] as? [[String: Any]] else {
            return ClaudeStats(todayMessages: 0, weekMessages: 0, todayTokens: 0, todaySessions: 0)
        }

        let today = dateString(Date())
        let weekAgo = dateString(Calendar.current.date(byAdding: .day, value: -7, to: Date())!)

        var todayMessages = 0, weekMessages = 0, todaySessions = 0

        for entry in dailyActivity {
            guard let date = entry["date"] as? String,
                  let count = entry["messageCount"] as? Int else { continue }
            if date == today {
                todayMessages = count
                todaySessions = (entry["sessionCount"] as? Int) ?? 0
            }
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

        return ClaudeStats(todayMessages: todayMessages, weekMessages: weekMessages,
                          todayTokens: todayTokens, todaySessions: todaySessions)
    }

    private func startClaudeCodeWatcher() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let statsPath = home.appendingPathComponent(".claude/stats-cache.json").path

        guard FileManager.default.fileExists(atPath: statsPath) else { return }

        let fd = open(statsPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend], queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self = self,
                  let config = self.settings.services.first(where: { $0.trackingMode == .claudeCodeLogs && $0.enabled }) else { return }
            self.refreshService(config)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        logWatcher = source
    }

    // MARK: - Connection tests

    private func testAnthropicKey(apiKey: String, completion: @escaping (Bool, String) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-4-20250514", "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ])
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 || http.statusCode == 429 {
                    completion(true, "API key valid")
                } else if http.statusCode == 401 {
                    completion(false, "Invalid API key")
                } else {
                    completion(true, "Connected (status \(http.statusCode))")
                }
            }
        }.resume()
    }

    private func testXAIKey(apiKey: String, completion: @escaping (Bool, String) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.x.ai/v1/models")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                completion(http.statusCode == 200, http.statusCode == 200 ? "Connected to xAI" : "Invalid key (status \(http.statusCode))")
            } else {
                completion(false, "Connection failed")
            }
        }.resume()
    }

    private func testTwitterKey(apiKey: String, completion: @escaping (Bool, String) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.twitter.com/2/users/me")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    completion(true, "Connected to Twitter/X")
                } else if http.statusCode == 401 {
                    completion(false, "Invalid bearer token")
                } else {
                    completion(false, "Error (status \(http.statusCode))")
                }
            } else {
                completion(false, "Connection failed")
            }
        }.resume()
    }

    private func testOpenAIKey(apiKey: String, completion: @escaping (Bool, String) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                completion(http.statusCode == 200, http.statusCode == 200 ? "Connected to OpenAI" : "Invalid key")
            } else {
                completion(false, "Connection failed")
            }
        }.resume()
    }

    // MARK: - API usage fetchers

    private func fetchAnthropicUsage(apiKey: String, completion: @escaping (Int, String) -> Void) {
        // Anthropic doesn't have a public usage endpoint yet
        // Read from Claude Code local stats as best proxy
        let stats = readClaudeCodeStats()
        completion(stats.todayMessages, "\(stats.todayTokens) tokens today")
    }

    private func fetchXAIUsage(apiKey: String, completion: @escaping (Int, Int, String) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "grok-3-mini", "max_tokens": 1,
            "messages": [["role": "user", "content": "."]]
        ])
        URLSession.shared.dataTask(with: req) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                let remaining = Int(http.value(forHTTPHeaderField: "x-ratelimit-remaining-requests") ?? "") ?? 0
                let limit = Int(http.value(forHTTPHeaderField: "x-ratelimit-limit-requests") ?? "") ?? 0
                let used = limit > 0 ? limit - remaining : 0
                completion(used, remaining, "\(remaining)/\(limit) requests remaining")
            } else {
                completion(0, 0, "Fetch failed")
            }
        }.resume()
    }

    struct TwitterRateInfo {
        var used: Int; var remaining: Int; var resetsAt: Date
    }

    private func fetchTwitterUsage(apiKey: String, completion: @escaping (TwitterRateInfo) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.twitter.com/2/users/me")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, response, _ in
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

    private func fetchOpenAIUsage(apiKey: String, completion: @escaping (Int, String) -> Void) {
        // OpenAI usage via billing API
        let today = dateString(Date())
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/usage?date=\(today)")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let totalRequests = json["total_requests"] as? Int {
                completion(totalRequests, "\(totalRequests) requests today")
            } else {
                // Fallback: just check rate limit headers
                if let http = response as? HTTPURLResponse {
                    let remaining = Int(http.value(forHTTPHeaderField: "x-ratelimit-remaining-requests") ?? "") ?? 0
                    let limit = Int(http.value(forHTTPHeaderField: "x-ratelimit-limit-requests") ?? "") ?? 0
                    completion(limit > 0 ? limit - remaining : 0, "\(remaining) remaining")
                } else {
                    completion(0, "Could not fetch usage")
                }
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
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - Helpers

    func nextDailyReset(hour: Int) -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = cal.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        var date = cal.date(from: c)!
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
