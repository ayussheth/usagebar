import Foundation

struct ServiceConfig: Codable, Identifiable {
    var id: String { name }
    var name: String
    var enabled: Bool
    var dailyLimit: Int       // max requests/tokens per day
    var weeklyLimit: Int      // max per week
    var apiKey: String        // for checking usage via API
    var notificationSound: String  // sound file name or "default"
    var resetHourUTC: Int     // hour when daily limit resets (UTC)

    static let defaults: [ServiceConfig] = [
        ServiceConfig(name: "Claude", enabled: true, dailyLimit: 100, weeklyLimit: 500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0),
        ServiceConfig(name: "Codex", enabled: true, dailyLimit: 200, weeklyLimit: 1000,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0),
        ServiceConfig(name: "Cursor", enabled: false, dailyLimit: 500, weeklyLimit: 2500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0),
        ServiceConfig(name: "Gemini", enabled: false, dailyLimit: 300, weeklyLimit: 1500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0),
        ServiceConfig(name: "Copilot", enabled: false, dailyLimit: 300, weeklyLimit: 1500,
                      apiKey: "", notificationSound: "default", resetHourUTC: 0),
    ]
}

struct UsageSnapshot: Codable {
    var dailyUsed: Int
    var weeklyUsed: Int
    var lastUpdated: Date
    var dailyResetsAt: Date
    var weeklyResetsAt: Date
    var limitReached: Bool

    static let empty = UsageSnapshot(
        dailyUsed: 0, weeklyUsed: 0,
        lastUpdated: Date(), dailyResetsAt: Date(),
        weeklyResetsAt: Date(), limitReached: false
    )
}

struct AppSettings: Codable {
    var services: [ServiceConfig]
    var globalNotificationsEnabled: Bool
    var customSoundPath: String?  // path to custom .aiff/.wav

    static let `default` = AppSettings(
        services: ServiceConfig.defaults,
        globalNotificationsEnabled: true,
        customSoundPath: nil
    )
}
