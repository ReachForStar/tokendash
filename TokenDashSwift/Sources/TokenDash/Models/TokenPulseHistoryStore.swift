import Foundation

/// Persists the rolling Token Pulse window so closing the popover or restarting
/// the app never resets the visible 30-minute history.
final class TokenPulseHistoryStore {
    static let shared = TokenPulseHistoryStore()

    private let windowDuration: TimeInterval = 30 * 60
    private let maximumSampleCount = 360
    private let fileURL: URL
    private let defaults = UserDefaults.standard
    private let directionDefinitionVersion = 2
    private let directionDefinitionKey = "pulse.directionDefinitionVersion"

    private init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let directory = applicationSupport.appendingPathComponent("TokenDash", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("pulse-history.json")
    }

    func load(now: Date = Date()) -> [TokenPulseSample] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let samples = try? JSONDecoder().decode([TokenPulseSample].self, from: data)
        else {
            defaults.set(directionDefinitionVersion, forKey: directionDefinitionKey)
            return []
        }

        let recent = trimmed(samples, now: now)
        guard defaults.integer(forKey: directionDefinitionKey) < directionDefinitionVersion else {
            return recent
        }

        // Version 1 derived Input from total-output, which incorrectly included
        // cache usage. Preserve total history but discard its invalid direction.
        let migrated = recent.map {
            TokenPulseSample(
                timestamp: $0.timestamp,
                tokenDelta: $0.tokenDelta,
                tokensPerSecond: $0.tokensPerSecond
            )
        }
        defaults.set(directionDefinitionVersion, forKey: directionDefinitionKey)
        save(migrated, now: now)
        return migrated
    }

    func save(_ samples: [TokenPulseSample], now: Date = Date()) {
        defaults.set(directionDefinitionVersion, forKey: directionDefinitionKey)
        let recent = trimmed(samples, now: now)
        guard let data = try? JSONEncoder().encode(recent) else { return }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[TokenDash] Failed to persist pulse history: \(error)")
        }
    }

    private func trimmed(_ samples: [TokenPulseSample], now: Date) -> [TokenPulseSample] {
        let cutoff = now.addingTimeInterval(-windowDuration)
        return samples
            .filter { $0.timestamp >= cutoff && $0.timestamp <= now.addingTimeInterval(5) }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(maximumSampleCount)
            .map { $0 }
    }
}
