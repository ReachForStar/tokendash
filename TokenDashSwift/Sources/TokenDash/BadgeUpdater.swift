import Foundation
import AppKit

/// Periodically fetches usage data from the API, updates the menu bar badge image
/// and refreshes the shared AppState for the popover.
///
/// Refresh is driven by a three-state machine (`RefreshMode`) instead of a fixed
/// high-frequency timer:
/// - `.dormant`  — popover closed: only the cheap badge update (today total),
///                 served from the daemon cache. No pulse, no details, no quota.
/// - `.active`   — popover open: immediate full refresh + 10s pulse (refresh,
///                 for rate deltas) + 60s cached detail refresh.
/// - `.suspended`— system sleep / low power: all data timers stopped.
@MainActor class BadgeUpdater {
    private let state: AppState
    private var apiClient: (any APIClientProtocol)?

    enum RefreshMode { case dormant, active, suspended }
    private(set) var mode: RefreshMode = .dormant

    // Cadences (seconds). dormant reuses the user's SettingsStore.refreshInterval
    // (it is cache-served, so even 30s stays cheap). active cadences are fixed.
    private var dormantInterval: TimeInterval { SettingsStore.shared.refreshInterval.rawValue }
    private let activePulseInterval: TimeInterval = 10.0
    private let activeFullInterval: TimeInterval = 60.0

    private var dormantTimer: Timer?
    private var pulseTimer: Timer?
    private var fullTimer: Timer?

    private var activeAgents: [String] = []
    private var isPulseSampling = false
    private var lastPulseObservation: (
        date: String,
        timestamp: Date,
        totalTokens: Int,
        inputTokens: Int,
        outputTokens: Int
    )?

    init(state: AppState, client: (any APIClientProtocol)? = nil) {
        self.state = state
        self.apiClient = client
    }

    func start(port: Int) {
        applyPort(port)
        setMode(.dormant)   // app launches with popover hidden
    }

    /// Hot-switch to a new daemon port after restart, preserving the current mode.
    func updatePort(_ port: Int) {
        let resumeMode = mode
        applyPort(port)
        NSLog("[TokenDash] BadgeUpdater switched to port \(port)")
        mode = .suspended     // force setMode to rebuild timers against new port
        setMode(resumeMode)
    }

    private func applyPort(_ port: Int) {
        self.apiClient = APIClient(port: port)
        self.state.daemonPort = port
        self.state.isDaemonReady = true
        self.state.errorMessage = nil
    }

    // MARK: - Mode state machine

    func setMode(_ newMode: RefreshMode) {
        mode = newMode
        stopDataTimers()
        switch newMode {
        case .dormant:
            scheduleDormant()
            Task { await self.performBadgeUpdate() }   // immediate refresh on entry
        case .active:
            Task { await self.performFullUpdate(forceRefresh: true, forceQuota: false) }
            schedulePulse()
            scheduleActiveFull()
        case .suspended:
            break   // all data timers stopped; daemon healthCheck (AppDelegate) keeps running
        }
        NSLog("[TokenDash] BadgeUpdater mode → \(newMode)")
    }

    private func scheduleDormant() {
        let t = Timer(timeInterval: dormantInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.performBadgeUpdate() }
        }
        RunLoop.main.add(t, forMode: .common)
        dormantTimer = t
    }

    private func schedulePulse() {
        let t = Timer(timeInterval: activePulseInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.samplePulse() }
        }
        RunLoop.main.add(t, forMode: .common)
        pulseTimer = t
    }

    private func scheduleActiveFull() {
        let t = Timer(timeInterval: activeFullInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.performFullUpdate(forceRefresh: false, forceQuota: false) }
        }
        RunLoop.main.add(t, forMode: .common)
        fullTimer = t
    }

    private func stopDataTimers() {
        dormantTimer?.invalidate(); dormantTimer = nil
        pulseTimer?.invalidate(); pulseTimer = nil
        fullTimer?.invalidate(); fullTimer = nil
    }

    func stop() {
        stopDataTimers()
    }

    /// Manual refresh (refresh button) — force everything, including external quota.
    func refreshNow() {
        Task { await self.performFullUpdate(forceRefresh: true, forceQuota: true) }
    }

    // MARK: - dormant: cheap badge update (cache-served)

    /// Updates only today's total tokens + cost for the menu bar badge. Served
    /// from the daemon's 5min cache (refresh:false) so it never triggers JSONL
    /// re-parsing. Does not touch detail state (hourly/projects/trend/quota).
    func performBadgeUpdate() async {
        guard let api = apiClient else { return }
        do {
            let agentsResp = try await api.getAgents()
            let agents = agentsResp.available.isEmpty ? ["claude"] : agentsResp.available
            self.activeAgents = agents

            let today = todayString()
            var totalTokens = 0
            var totalCost = 0.0
            for agent in agents {
                if let d = try? await api.getDaily(agent: agent, refresh: false) {
                    if let entry = d.daily.first(where: { $0.date == today }) {
                        totalTokens += entry.totalTokens
                        totalCost += entry.totalCost
                    }
                }
            }

            let tokenStr = formatTokens(totalTokens)
            self.state.badgeImage = Self.renderBadgeImage(title: tokenStr)
            self.state.tooltipText = String(
                format: "TokenDash - %@ tokens today ($%.2f)", tokenStr, totalCost)
            self.state.isLoading = false
            self.state.errorMessage = nil
        } catch {
            NSLog("[TokenDash] badge update error: \(error.localizedDescription)")
            self.state.errorMessage = error.localizedDescription
        }
    }

    // MARK: - active: full popover refresh

    /// Full refresh for the open popover: daily + blocks + projects + quota +
    /// derived hourly/projects/models/trend. `forceRefresh` bypasses the daemon
    /// usage cache (used on popover open); `forceQuota` bypasses the 60s quota
    /// cache (manual refresh only).
    func performFullUpdate(forceRefresh: Bool, forceQuota: Bool) async {
        guard let api = apiClient else {
            NSLog("[TokenDash] performFullUpdate called but apiClient is nil")
            return
        }
        do {
            let agentsResp = try await api.getAgents()
            let agents = agentsResp.available.isEmpty ? ["claude"] : agentsResp.available
            self.activeAgents = agents

            var dailyResults: [DailyResponse] = []
            var blockResults: [BlocksResponse] = []
            var projectResults: [ProjectsResponse] = []

            for agent in agents {
                if let d = try? await api.getDaily(agent: agent, refresh: forceRefresh) { dailyResults.append(d) }
                // Detail endpoints always cache-served (refresh:false) — daemon reuses its
                // 5min cache, so the 60s active cadence does NOT re-parse JSONL.
                if let b = try? await api.getBlocks(agent: agent, refresh: false) { blockResults.append(b) }
                if let p = try? await api.getProjects(agent: agent, refresh: false) { projectResults.append(p) }
            }

            let today = todayString()
            var totalTokens = 0, totalInput = 0, totalOutput = 0, totalCacheRead = 0
            var totalCost = 0.0
            for data in dailyResults {
                guard let entry = data.daily.first(where: { $0.date == today }) else { continue }
                totalTokens += entry.totalTokens
                totalInput += entry.inputTokens
                totalOutput += entry.outputTokens
                totalCacheRead += entry.cacheReadTokens
                totalCost += entry.totalCost
            }
            let denom = Double(totalInput + totalCacheRead)
            let cacheRate = denom > 0 ? Double(totalCacheRead) / denom * 100 : 0
            let tokenStr = formatTokens(totalTokens)
            let badgeImage = Self.renderBadgeImage(title: tokenStr)
            let summary = TodaySummary(
                tokens: totalTokens, cost: totalCost,
                inputTokens: totalInput, outputTokens: totalOutput,
                cacheReadTokens: totalCacheRead, cacheRate: cacheRate)
            if dailyResults.count == agents.count {
                self.recordPulseObservation(
                    totalTokens: totalTokens, inputTokens: totalInput, outputTokens: totalOutput,
                    date: today, at: Date())
            }
            let hourly = computeHourly(blocks: blockResults, today: today)
            let projectRows = computeProjects(projects: projectResults, today: today)
            let modelRows = computeModels(daily: dailyResults, today: today)
            let trendPoints = computeTrend(daily: dailyResults)

            // Coding Plan quotas — cache-served unless this is a manual refresh.
            var quotaSnapshots = self.state.quotas
            do {
                let quotaResp = try await api.getQuota(refresh: forceQuota)
                quotaSnapshots = self.retainUsableQuotas(quotaResp.providers, previous: self.state.quotas)
            } catch {
                NSLog("[TokenDash] Quota fetch failed (non-fatal): \(error)")
            }

            self.state.badgeImage = badgeImage
            self.state.tooltipText = String(
                format: "TokenDash - %@ tokens today ($%.2f) | cache: %.1f%%",
                tokenStr, totalCost, cacheRate)
            self.state.todaySummary = summary
            self.state.cacheRate = cacheRate
            self.state.isLoading = false
            self.state.errorMessage = nil
            self.state.hourlyData = hourly
            self.state.projects = projectRows
            self.state.models = modelRows
            self.state.trend = trendPoints
            self.state.quotas = quotaSnapshots

            NotificationService.shared.evaluate(quotas: quotaSnapshots)
        } catch {
            NSLog("[TokenDash] full update error: \(error.localizedDescription)")
            self.state.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pulse sampling (active only)

    /// Samples today's cumulative token count every activePulseInterval. refresh:true
    /// because rate deltas need fresh totals (a cache-served value would freeze the
    /// rate chart at zero). Only scheduled in `.active`.
    private func samplePulse() {
        guard let api = apiClient, !isPulseSampling else { return }
        isPulseSampling = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isPulseSampling = false }
            do {
                let agents: [String]
                if self.activeAgents.isEmpty {
                    let resp = try await api.getAgents()
                    agents = resp.available.isEmpty ? ["claude"] : resp.available
                } else {
                    agents = self.activeAgents
                }
                let today = todayString()
                var totalTokens = 0, inputTokens = 0, outputTokens = 0, ok = 0
                for agent in agents {
                    do {
                        let r = try await api.getDaily(agent: agent, refresh: true)
                        if let e = r.daily.first(where: { $0.date == today }) {
                            totalTokens += e.totalTokens
                            inputTokens += e.inputTokens
                            outputTokens += e.outputTokens
                        }
                        ok += 1
                    } catch {
                        NSLog("[TokenDash] Pulse sample failed for \(agent): \(error)")
                    }
                }
                guard ok == agents.count else { return }
                self.recordPulseObservation(
                    totalTokens: totalTokens, inputTokens: inputTokens, outputTokens: outputTokens,
                    date: today, at: Date())
            } catch {
                NSLog("[TokenDash] Pulse sampling failed: \(error)")
            }
        }
    }

    private func recordPulseObservation(
        totalTokens: Int, inputTokens: Int, outputTokens: Int, date: String, at timestamp: Date
    ) {
        guard let previous = lastPulseObservation, previous.date == date else {
            lastPulseObservation = (date, timestamp, totalTokens, inputTokens, outputTokens)
            if let latest = state.pulseSamples.last,
               !Calendar.current.isDate(latest.timestamp, inSameDayAs: timestamp) {
                state.pulseSamples = []
                TokenPulseHistoryStore.shared.save([], now: timestamp)
            }
            return
        }
        let elapsed = timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return }
        // A lower total means the source was reset or reparsed. Reset the
        // baseline instead of drawing a false negative spike.
        let delta = totalTokens >= previous.totalTokens ? totalTokens - previous.totalTokens : 0
        let inputDelta = inputTokens >= previous.inputTokens ? inputTokens - previous.inputTokens : 0
        let outputDelta = outputTokens >= previous.outputTokens ? outputTokens - previous.outputTokens : 0
        let sample = TokenPulseSample(
            timestamp: timestamp,
            tokenDelta: delta,
            tokensPerSecond: Double(delta) / elapsed,
            inputDelta: inputDelta,
            outputDelta: outputDelta,
            inputTokensPerSecond: Double(inputDelta) / elapsed,
            outputTokensPerSecond: Double(outputDelta) / elapsed
        )
        let cutoff = timestamp.addingTimeInterval(-30 * 60)
        state.pulseSamples = (state.pulseSamples + [sample])
            .filter { $0.timestamp >= cutoff }
            .suffix(360)
            .map { $0 }
        TokenPulseHistoryStore.shared.save(state.pulseSamples, now: timestamp)
        lastPulseObservation = (date, timestamp, totalTokens, inputTokens, outputTokens)
    }

    private func retainUsableQuotas(_ incoming: [QuotaSnapshot], previous: [QuotaSnapshot]) -> [QuotaSnapshot] {
        guard !incoming.isEmpty else { return previous }
        let previousByProvider = Dictionary(uniqueKeysWithValues: previous.map { ($0.provider, $0) })
        var retainedProviders = Set<String>()
        var merged = incoming.compactMap { snapshot -> QuotaSnapshot? in
            retainedProviders.insert(snapshot.provider)
            if snapshot.status.state == "ok", snapshot.freshness != "stale", !snapshot.windows.isEmpty {
                return snapshot
            }
            return previousByProvider[snapshot.provider]
        }
        for snapshot in previous where !retainedProviders.contains(snapshot.provider) {
            merged.append(snapshot)
        }
        return merged
    }

    // MARK: - Data computation

    private func computeHourly(blocks: [BlocksResponse], today: String) -> [HourBucket] {
        var hourly = [Int](repeating: 0, count: 24)
        for resp in blocks {
            for block in resp.blocks {
                let prefix = String(block.startTime.prefix(10))
                guard prefix == today else { continue }
                let hourStr = block.startTime.count >= 13 ? String(block.startTime.prefix(13).suffix(2)) : ""
                if let h = Int(hourStr), h >= 0, h < 24 {
                    hourly[h] += block.totalTokens
                }
            }
        }
        let maxVal = hourly.max() ?? 0
        return (0..<24).map { h in
            HourBucket(hour: h, tokens: hourly[h], isPeak: hourly[h] > 0 && hourly[h] == maxVal)
        }
    }

    private func computeProjects(projects: [ProjectsResponse], today: String) -> [ProjectRow] {
        var totals: [String: (input: Int, output: Int, cached: Int, total: Int)] = [:]
        for resp in projects {
            for (path, entries) in resp.projects {
                let todayEntries = entries.filter { $0.date == today }
                guard !todayEntries.isEmpty else { continue }
                var t = totals[path] ?? (0, 0, 0, 0)
                for e in todayEntries {
                    t.input += e.inputTokens
                    t.output += e.outputTokens
                    t.cached += e.cacheReadTokens
                    t.total += e.totalTokens
                }
                totals[path] = t
            }
        }
        return totals.map { path, t in
            ProjectRow(name: formatProjectName(path), fullPath: path, input: t.input, output: t.output, cached: t.cached, total: t.total)
        }.sorted { $0.total > $1.total }.prefix(4).map { $0 }
    }

    /// Aggregate today's per-model usage across all agents (uses modelBreakdowns
    /// that the summary loop discards). Token count = input + output + cacheRead.
    private func computeModels(daily: [DailyResponse], today: String) -> [ModelRow] {
        var totals: [String: (tokens: Int, cost: Double)] = [:]
        for data in daily {
            guard let entry = data.daily.first(where: { $0.date == today }) else { continue }
            for b in entry.modelBreakdowns ?? [] {
                let name = shortModelName(b.modelName)
                var t = totals[name] ?? (0, 0)
                t.tokens += b.inputTokens + b.outputTokens + b.cacheReadTokens
                t.cost += b.cost
                totals[name] = t
            }
        }
        return totals.map { name, t in
            ModelRow(name: name, tokens: t.tokens, cost: t.cost)
        }.sorted { $0.tokens > $1.tokens }.prefix(5).map { $0 }
    }

    /// Last 7 days (oldest → newest) aggregated cost + tokens across all agents.
    private func computeTrend(daily: [DailyResponse]) -> [TrendPoint] {
        var byDate: [String: (tokens: Int, cost: Double)] = [:]
        for data in daily {
            for entry in data.daily {
                var t = byDate[entry.date] ?? (0, 0)
                t.tokens += entry.totalTokens
                t.cost += entry.totalCost
                byDate[entry.date] = t
            }
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { i in
            guard let d = cal.date(byAdding: .day, value: -i, to: todayStart) else {
                return TrendPoint(date: "", tokens: 0, cost: 0)
            }
            let key = fmt.string(from: d)
            let t = byDate[key] ?? (0, 0)
            return TrendPoint(date: key, tokens: t.tokens, cost: t.cost)
        }
    }

    // MARK: - Badge image rendering

    static func renderBadgeImage(title: String) -> NSImage {
        let iconW: CGFloat = 18, iconH: CGFloat = 18
        let fontSize: CGFloat = 13
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let textWidth = (title as NSString).size(withAttributes: textAttrs).width
        let padding: CGFloat = 4
        let totalWidth = iconW + padding + textWidth
        let totalHeight: CGFloat = 20

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()

        // Draw a compact circular token mark for menu bar legibility.
        let icon = createTemplateIcon(size: NSSize(width: iconW, height: iconH))
        let iconY = (totalHeight - iconH) / 2.0
        icon.draw(in: NSRect(x: 0, y: iconY, width: iconW, height: iconH))

        // Draw text
        let textY = (totalHeight - fontSize) / 2.0 - 1
        (title as NSString).draw(at: NSPoint(x: iconW + padding, y: textY), withAttributes: textAttrs)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func createTemplateIcon(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let inset = min(size.width, size.height) * 0.08
        let circleRect = NSRect(
            x: inset,
            y: inset,
            width: size.width - inset * 2,
            height: size.height - inset * 2
        )
        NSColor.black.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        // Cut the app icon's pulse line out of the circular token mark.
        let sx = size.width / 64.0
        let sy = size.height / 64.0
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 7 * sx, y: 32 * sy))
        path.line(to: NSPoint(x: 25 * sx, y: 32 * sy))
        path.line(to: NSPoint(x: 31 * sx, y: 47 * sy))
        path.line(to: NSPoint(x: 38 * sx, y: 17 * sy))
        path.line(to: NSPoint(x: 44 * sx, y: 32 * sy))
        path.line(to: NSPoint(x: 57 * sx, y: 32 * sy))
        path.lineWidth = 5.5 * sx
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
