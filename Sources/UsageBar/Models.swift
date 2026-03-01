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
    var connected: Bool

    enum TrackingMode: String, Codable, CaseIterable {
        case manual = "Manual"
        case claudeCodeLogs = "Claude Code Logs"
        case anthropicAPI = "Anthropic API"
        case xaiAPI = "xAI/Grok API"
        case twitterAPI = "Twitter/X API"
        case openaiAPI = "OpenAI API"
    }

    static let defaults: [ServiceConfig] = [
        ServiceConfig(name: "Claude Code", enabled: true, dailyLimit: 200, weeklyLimit: 1000,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .claudeCodeLogs, connected: false),
        ServiceConfig(name: "Claude API", enabled: false, dailyLimit: 1000, weeklyLimit: 5000,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .anthropicAPI, connected: false),
        ServiceConfig(name: "Grok", enabled: false, dailyLimit: 300, weeklyLimit: 1500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .xaiAPI, connected: false),
        ServiceConfig(name: "Twitter/X", enabled: false, dailyLimit: 500, weeklyLimit: 2500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .twitterAPI, connected: false),
        ServiceConfig(name: "OpenAI", enabled: false, dailyLimit: 500, weeklyLimit: 2500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0,
                      trackingMode: .openaiAPI, connected: false),
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
    var status: ConnectionStatus

    enum ConnectionStatus: String, Codable {
        case connected = "Connected"
        case disconnected = "Disconnected"
        case error = "Error"
        case checking = "Checking..."
    }

    static let empty = UsageSnapshot(
        dailyUsed: 0, weeklyUsed: 0,
        lastUpdated: Date(), dailyResetsAt: Date(),
        weeklyResetsAt: Date(), limitReached: false,
        detail: nil, status: .disconnected
    )
}

struct AppSettings: Codable {
    var services: [ServiceConfig]
    var globalNotificationsEnabled: Bool
    var customSoundPath: String?
    var refreshIntervalSeconds: Int

    static let `default` = AppSettings(
        services: ServiceConfig.defaults,
        globalNotificationsEnabled: true,
        customSoundPath: nil,
        refreshIntervalSeconds: 60
    )
}
