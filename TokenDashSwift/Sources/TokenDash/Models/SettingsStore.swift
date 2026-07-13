import Foundation
import SwiftUI

/// User-configurable settings, persisted to UserDefaults and observable so the
/// popover + badge updater react to changes. Singleton (mirrors AppState).
@Observable final class SettingsStore {
    static let shared = SettingsStore()

    /// How often popover detail data refreshes in the background.
    enum RefreshInterval: Double, CaseIterable, Identifiable {
        case tenMinutes = 600
        case thirtyMinutes = 1_800
        case oneHour = 3_600
        var id: Double { rawValue }
        var label: String {
            switch self {
            case .tenMinutes: return "10 min"
            case .thirtyMinutes: return "30 min"
            case .oneHour: return "1 hour (Low Power)"
            }
        }
    }

    /// Popover appearance.
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "Match System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }
    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    var lowQuotaNotificationsEnabled: Bool {
        didSet { defaults.set(lowQuotaNotificationsEnabled, forKey: Keys.lowQuotaNotif) }
    }
    var lowQuotaThreshold: Int {
        didSet { defaults.set(lowQuotaThreshold, forKey: Keys.lowQuotaThreshold) }
    }
    var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let refreshInterval = "settings.refreshInterval"
        static let appearance = "settings.appearance"
        static let lowQuotaNotif = "settings.lowQuotaNotifications"
        static let lowQuotaThreshold = "settings.lowQuotaThreshold"
        static let autoCheckUpdates = "settings.autoCheckUpdates"
    }

    private init() {
        let d = UserDefaults.standard
        let storedRefreshRaw = d.object(forKey: Keys.refreshInterval) as? Double
        let refreshInterval = storedRefreshRaw
            .flatMap(RefreshInterval.init(rawValue:)) ?? .oneHour
        self.refreshInterval = refreshInterval
        if storedRefreshRaw != refreshInterval.rawValue {
            d.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
        }
        let appRaw = d.string(forKey: Keys.appearance) ?? Appearance.system.rawValue
        self.appearance = Appearance(rawValue: appRaw) ?? .system
        self.lowQuotaNotificationsEnabled = d.object(forKey: Keys.lowQuotaNotif) as? Bool ?? true
        self.lowQuotaThreshold = d.object(forKey: Keys.lowQuotaThreshold) as? Int ?? 80
        self.autoCheckUpdates = d.object(forKey: Keys.autoCheckUpdates) as? Bool ?? true
    }
}
