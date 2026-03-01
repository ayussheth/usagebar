import Foundation

struct ServiceConfig: Codable, Identifiable {
    var id: String { name }
    var name: String
    var enabled: Bool
    var dailyLimit: Int
    var weeklyLimit: Int
    var apiKey: String
    var notificationSound: String
    var resetHourUTC: Int
    var trackingMode: TrackingMode

    enum TrackingMode: String, Codable, CaseIterable {
        case manual = "Manual"
        case claudeCodeLogs = "Claude Code Logs"
        case anthropicAPI = "Anthropic API"
        case xaiAPI = "xAI API"
        case twitterAPI = "Twitter API"
    }

    static let defaults: [ServiceConfig] = [
        ServiceConfig(name: "Claude Code", enabled: true, dailyLimit: 200, weeklyLimit: 1000,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .claudeCodeLogs),
        ServiceConfig(name: "Claude API", enabled: true, dailyLimit: 500, weeklyLimit: 2500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .anthropicAPI),
        ServiceConfig(name: "Grok", enabled: true, dailyLimit: 300, weeklyLimit: 1500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .xaiAPI),
        ServiceConfig(name: "Twitter/X", enabled: true, dailyLimit: 500, weeklyLimit: 2500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .twitterAPI),
        ServiceConfig(name: "Cursor", enabled: false, dailyLimit: 500, weeklyLimit: 2500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .manual),
        ServiceConfig(name: "Copilot", enabled: false, dailyLimit: 300, weeklyLimit: 1500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .manual),
    ]
}

struct UsageSnapshot: Codable {
    var dailyUsed: Int
    var weeklyUsed: Int
    var lastUpdated: Date
    var dailyResetsAt: Date
    var weeklyResetsAt: Date
    var limitReached: Bool
    var detail: String?

    static let empty = UsageSnapshot(
        dailyUsed: 0, weeklyUsed: 0,
        lastUpdated: Date(), dailyResetsAt: Date(),
        weeklyResetsAt: Date(), limitReached: false, detail: nil
    )
}

struct AppSettings: Codable {
    var services: [ServiceConfig]
    var globalNotificationsEnabled: Bool
    var customSoundPath: String?

    static let `default` = AppSettings(
        services: ServiceConfig.defaults,
        globalNotificationsEnabled: true,
        customSoundPath: nil
    )
}
