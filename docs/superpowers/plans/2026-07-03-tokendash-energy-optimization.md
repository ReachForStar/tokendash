# TokenDash 能耗优化（方案 A+ 自适应刷新）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 TokenDash 菜单栏的后台刷新从「无脑 5s 强解析」改成「popover 可见性 + 系统电源驱动的 dormant/active/suspended 三态」，让 popover 合上时 CPU 归零、打开时全速无损。

**Architecture:** `BadgeUpdater` 引入 `RefreshMode` 状态机，由 `AppDelegate` 在 NSPanel 开闭与系统睡眠/低电量通知时切换模式。每个模式只调度它需要的定时器：dormant 仅 60s（用户设置）轻量 badge 更新走 daemon 缓存；active 全量刷新 + 10s 脉冲 + 60s 详情缓存刷新；suspended 全停。daemon 端零改动——Swift 端把 `refresh:true` 改成 `refresh:false` 即可命中现有 5min usage 缓存与 60s quota 缓存。

**Tech Stack:** Swift / SwiftUI / AppKit（NSPanel + NSStatusItem）/ XCTest / Node daemon（零改动）。

**Spec:** `docs/superpowers/specs/2026-07-03-tokendash-energy-optimization-design.md`

---

## File Structure

- **Modify** `TokenDashSwift/Sources/TokenDash/Services/APIClient.swift`
  - 新增 `APIClientProtocol`，`APIClient` 遵循它。为 BadgeUpdater 注入 mock 提供测试 seam。
- **Modify** `TokenDashSwift/Sources/TokenDash/BadgeUpdater.swift`（核心重构）
  - 加 `RefreshMode` 状态机 + `setMode(_:)` + 三个独立定时器（dormant / active-pulse / active-full）。
  - 拆 `update()` 为 `performBadgeUpdate()`（轻，dormant）与 `performFullUpdate(forceRefresh:forceQuota:)`（重，active）。
  - `samplePulse()` 仅 active 调度；`refresh:false` 走缓存；`refreshNow()` 手动强刷含 quota。
- **Modify** `TokenDashSwift/Sources/TokenDash/App.swift`
  - `togglePopover()` 显示后 `setMode(.active)`；`hidePopover()` 后 `setMode(.dormant)`。
  - 注册 `NSWorkspace.willSleep/didWakeNotification` + `NSProcessInfoPowerStateDidChange`，驱动 suspended。
- **Create** `TokenDashSwift/Tests/TokenDashTests/BadgeUpdaterModeTests.swift`
  - XCTest，用 `MockAPIClient`（actor）计数，验证 dormant 不拉 blocks/projects/quota、active 走缓存。
- **daemon 端零改动**（已确认 `src/server/routes/daily.ts:14` 与 `api.ts:17` 在无 `refresh=1` 时走缓存）。

---

## Task 1: 抽出 `APIClientProtocol`（可测试性前置）

**Files:**
- Modify: `TokenDashSwift/Sources/TokenDash/Services/APIClient.swift`

- [ ] **Step 1: 在 `APIClient.swift` 顶部（`actor APIClient` 之前）新增协议**

在 `import Foundation` 之后、`actor APIClient` 之前插入：

```swift
/// Test seam — BadgeUpdater depends on this protocol so unit tests can inject
/// a counting mock instead of the real HTTP client.
protocol APIClientProtocol {
    func getAgents() async throws -> AgentsResponse
    func getDaily(agent: String, refresh: Bool) async throws -> DailyResponse
    func getBlocks(agent: String, refresh: Bool) async throws -> BlocksResponse
    func getProjects(agent: String, refresh: Bool) async throws -> ProjectsResponse
    func getQuota(refresh: Bool) async throws -> QuotaResponse
}
```

- [ ] **Step 2: 让 `APIClient` 遵循协议**

把 `actor APIClient {` 改为：

```swift
actor APIClient: APIClientProtocol {
```

现有方法签名已与协议匹配（默认参数值不计入协议要求，无需改动方法体）。

- [ ] **Step 3: 验证编译**

Run: `swift build --package-path TokenDashSwift 2>&1 | tail -20`
Expected: `Build complete!`（无错误）

- [ ] **Step 4: Commit**

```bash
git add TokenDashSwift/Sources/TokenDash/Services/APIClient.swift
git commit -m "Introduce APIClientProtocol as a test seam for BadgeUpdater"
```

---

## Task 2: `BadgeUpdater` 状态机重构（核心）

**Files:**
- Modify: `TokenDashSwift/Sources/TokenDash/BadgeUpdater.swift`（整体替换）

- [ ] **Step 1: 先写失败的模式测试**

Create `TokenDashSwift/Tests/TokenDashTests/BadgeUpdaterModeTests.swift`:

```swift
import XCTest
@testable import TokenDash

@MainActor
final class BadgeUpdaterModeTests: XCTestCase {

    // MARK: - dormant: badge 更新只拉 daily，不拉 blocks/projects/quota

    func testDormantPerformBadgeUpdateSkipsBlocksProjectsQuota() async throws {
        let state = AppState()
        let mock = MockAPIClient()
        let updater = BadgeUpdater(state: state, client: mock)

        await updater.performBadgeUpdate()

        let counts = await mock.snapshot()
        XCTAssertGreaterThan(counts.daily, 0, "dormant badge 更新必须拉 daily")
        XCTAssertEqual(counts.blocks, 0, "dormant 不得拉 blocks")
        XCTAssertEqual(counts.projects, 0, "dormant 不得拉 projects")
        XCTAssertEqual(counts.quota, 0, "dormant 不得拉 quota")
    }

    // MARK: - active: 打开瞬间全量拉详情，但 quota 走缓存（refresh=false）

    func testActivePerformFullUpdateFetchesDetailsButCachesQuota() async throws {
        let state = AppState()
        let mock = MockAPIClient()
        let updater = BadgeUpdater(state: state, client: mock)

        await updater.performFullUpdate(forceRefresh: true, forceQuota: false)

        let counts = await mock.snapshot()
        XCTAssertGreaterThan(counts.daily, 0)
        XCTAssertGreaterThan(counts.blocks, 0)
        XCTAssertGreaterThan(counts.projects, 0)
        XCTAssertGreaterThan(counts.quota, 0, "active 详情刷新要拉 quota")
        let lastQuotaRefresh = await mock.lastQuotaRefresh
        XCTAssertEqual(lastQuotaRefresh, false, "非手动刷新时 quota 必须走缓存")
    }

    // MARK: - 手动刷新：quota 强刷

    func testManualRefreshForceRefreshesQuota() async throws {
        let state = AppState()
        let mock = MockAPIClient()
        let updater = BadgeUpdater(state: state, client: mock)

        await updater.performFullUpdate(forceRefresh: true, forceQuota: true)

        let lastQuotaRefresh = await mock.lastQuotaRefresh
        XCTAssertEqual(lastQuotaRefresh, true, "手动刷新必须强刷 quota")
    }
}
```

- [ ] **Step 2: 写 MockAPIClient（同文件，测试辅助）**

在 `BadgeUpdaterModeTests.swift` 末尾追加：

```swift
/// 计数型 mock — 记录每个端点被调用的次数与关键参数，供模式断言。
actor MockAPIClient: APIClientProtocol {
    private(set) var agents = 0
    private(set) var daily = 0
    private(set) var blocks = 0
    private(set) var projects = 0
    private(set) var quota = 0
    private(set) var lastQuotaRefresh: Bool? = nil

    struct Snapshot {
        let agents: Int; let daily: Int; let blocks: Int
        let projects: Int; let quota: Int
    }
    func snapshot() -> Snapshot {
        Snapshot(agents: agents, daily: daily, blocks: blocks, projects: projects, quota: quota)
    }

    func getAgents() async throws -> AgentsResponse {
        agents += 1
        return AgentsResponse(available: ["claude"], default: "claude")
    }
    func getDaily(agent: String, refresh: Bool) async throws -> DailyResponse {
        daily += 1
        return DailyResponse(daily: [])
    }
    func getBlocks(agent: String, refresh: Bool) async throws -> BlocksResponse {
        blocks += 1
        return BlocksResponse(blocks: [])
    }
    func getProjects(agent: String, refresh: Bool) async throws -> ProjectsResponse {
        projects += 1
        return ProjectsResponse(projects: [:])
    }
    func getQuota(refresh: Bool) async throws -> QuotaResponse {
        quota += 1
        lastQuotaRefresh = refresh
        return QuotaResponse(providers: [])
    }
}
```

- [ ] **Step 3: 运行测试确认失败（BadgeUpdater 新 API 尚未实现）**

Run: `swift test --package-path TokenDashSwift --filter BadgeUpdaterModeTests 2>&1 | tail -30`
Expected: 编译失败 —— `BadgeUpdater` 没有 `init(state:client:)`、`performBadgeUpdate()`、`performFullUpdate(forceRefresh:forceQuota:)`。

- [ ] **Step 4: 整体替换 `BadgeUpdater.swift` 为重构版**

Replace the entire contents of `TokenDashSwift/Sources/TokenDash/BadgeUpdater.swift` with:

```swift
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
    private var apiClient: any APIClientProtocol?

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
                let agents = self.activeAgents.isEmpty
                    ? (try await api.getAgents().available.isEmpty ? ["claude"] : try await api.getAgents().available)
                    : self.activeAgents
                let today = self.todayString()
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
                    } catch { NSLog("[TokenDash] Pulse sample failed for \(agent): \(error)") }
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
        let delta = totalTokens >= previous.totalTokens ? totalTokens - previous.totalTokens : 0
        let inputDelta = inputTokens >= previous.inputTokens ? inputTokens - previous.inputTokens : 0
        let outputDelta = outputTokens >= previous.outputTokens ? outputTokens - previous.outputTokens : 0
        let sample = TokenPulseSample(
            timestamp: timestamp, tokenDelta: delta, tokensPerSecond: Double(delta) / elapsed,
            inputDelta: inputDelta, outputTokensPerSecond: Double(outputDelta) / elapsed,
            inputTokensPerSecond: Double(inputDelta) / elapsed,
            outputDelta: outputDelta)
        let _ = sample  // silence unused-warning path if any
        let cutoff = timestamp.addingTimeInterval(-30 * 60)
        state.pulseSamples = (state.pulseSamples + [sample])
            .filter { $0.timestamp >= cutoff }.suffix(360).map { $0 }
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
        for snapshot in previous where !retainedProviders.contains(snapshot.provider) { merged.append(snapshot) }
        return merged
    }

    // MARK: - Data computation (unchanged from prior implementation)

    private func computeHourly(blocks: [BlocksResponse], today: String) -> [HourBucket] {
        var hourly = [Int](repeating: 0, count: 24)
        for resp in blocks {
            for block in resp.blocks {
                let prefix = String(block.startTime.prefix(10))
                guard prefix == today else { continue }
                let hourStr = block.startTime.count >= 13 ? String(block.startTime.prefix(13).suffix(2)) : ""
                if let h = Int(hourStr), h >= 0, h < 24 { hourly[h] += block.totalTokens }
            }
        }
        let maxVal = hourly.max() ?? 0
        return (0..<24).map { h in HourBucket(hour: h, tokens: hourly[h], isPeak: hourly[h] > 0 && hourly[h] == maxVal) }
    }

    private func computeProjects(projects: [ProjectsResponse], today: String) -> [ProjectRow] {
        var totals: [String: (input: Int, output: Int, cached: Int, total: Int)] = [:]
        for resp in projects {
            for (path, entries) in resp.projects {
                let todayEntries = entries.filter { $0.date == today }
                guard !todayEntries.isEmpty else { continue }
                var t = totals[path] ?? (0, 0, 0, 0)
                for e in todayEntries {
                    t.input += e.inputTokens; t.output += e.outputTokens
                    t.cached += e.cacheReadTokens; t.total += e.totalTokens
                }
                totals[path] = t
            }
        }
        return totals.map { path, t in
            ProjectRow(name: formatProjectName(path), fullPath: path, input: t.input, output: t.output, cached: t.cached, total: t.total)
        }.sorted { $0.total > $1.total }.prefix(4).map { $0 }
    }

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
        return totals.map { name, t in ModelRow(name: name, tokens: t.tokens, cost: t.cost) }
            .sorted { $0.tokens > $1.tokens }.prefix(5).map { $0 }
    }

    private func computeTrend(daily: [DailyResponse]) -> [TrendPoint] {
        var byDate: [String: (tokens: Int, cost: Double)] = [:]
        for data in daily {
            for entry in data.daily {
                var t = byDate[entry.date] ?? (0, 0)
                t.tokens += entry.totalTokens; t.cost += entry.totalCost
                byDate[entry.date] = t
            }
        }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
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

    // MARK: - Badge image rendering (unchanged)

    static func renderBadgeImage(title: String) -> NSImage {
        let iconW: CGFloat = 18, iconH: CGFloat = 18
        let fontSize: CGFloat = 13
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textWidth = (title as NSString).size(withAttributes: textAttrs).width
        let padding: CGFloat = 4
        let totalWidth = iconW + padding + textWidth
        let totalHeight: CGFloat = 20
        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()
        let icon = createTemplateIcon(size: NSSize(width: iconW, height: iconH))
        icon.draw(in: NSRect(x: 0, y: (totalHeight - iconH) / 2.0, width: iconW, height: iconH))
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
        let circleRect = NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: circleRect).fill()
        let sx = size.width / 64.0, sy = size.height / 64.0
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 7 * sx, y: 32 * sy))
        path.line(to: NSPoint(x: 25 * sx, y: 32 * sy))
        path.line(to: NSPoint(x: 31 * sx, y: 47 * sy))
        path.line(to: NSPoint(x: 38 * sx, y: 17 * sy))
        path.line(to: NSPoint(x: 44 * sx, y: 32 * sy))
        path.line(to: NSPoint(x: 57 * sx, y: 32 * sy))
        path.lineWidth = 5.5 * sx
        path.lineCapStyle = .round; path.lineJoinStyle = .round
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
```

> **Note on `samplePulse` agent reload:** the original always re-fetched agents lazily; the refactor reuses `activeAgents` (populated by the full update on popover open) and only falls back to `getAgents()` when empty, trimming one network call per pulse tick.

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test --package-path TokenDashSwift --filter BadgeUpdaterModeTests 2>&1 | tail -30`
Expected: 3 个测试全部 PASS。

- [ ] **Step 6: 运行全部测试确认无回归**

Run: `swift test --package-path TokenDashSwift 2>&1 | tail -30`
Expected: 全部 PASS（含既有 `TokenPulseMetricsTests`）。

- [ ] **Step 7: Commit**

```bash
git add TokenDashSwift/Sources/TokenDash/BadgeUpdater.swift TokenDashSwift/Tests/TokenDashTests/BadgeUpdaterModeTests.swift
git commit -m "Refactor BadgeUpdater into dormant/active/suspended refresh state machine"
```

---

## Task 3: `AppDelegate` 集成模式切换 + 系统电源感知

**Files:**
- Modify: `TokenDashSwift/Sources/TokenDash/App.swift`

- [ ] **Step 1: 在 `togglePopover()` 的显示分支末尾（`startOutsideClickMonitor()` 之后）切 active**

定位 `App.swift` 中 `togglePopover()` 的 `else` 分支，在 `startOutsideClickMonitor()` 之后加一行：

```swift
            panel.orderFrontRegardless()
            panel.makeKey()
            startOutsideClickMonitor()
            badgeUpdater?.setMode(.active)   // ← 新增
```

- [ ] **Step 2: 在 `hidePopover()` 中（`orderOut` 之后）切 dormant**

```swift
    private func hidePopover() {
        panel.orderOut(nil)
        stopOutsideClickMonitor()
        badgeUpdater?.setMode(.dormant)     // ← 新增
    }
```

- [ ] **Step 3: 在 `applicationDidFinishLaunching` 里注册电源通知**

在 `daemonHealthTimer = Timer.scheduledTimer(...)` 之后、`DispatchQueue.main.async { ... }` 之前插入：

```swift
        // Power awareness: suspend the refresh state machine on sleep / low power
        // so the menu bar stops polling entirely while the system is idle.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(systemWillSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(systemDidWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(powerStateChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
```

- [ ] **Step 4: 新增三个 `@objc` 电源回调方法**

在 `checkDaemonHealth()` 方法之后（`applicationWillTerminate` 之前）插入：

```swift
    // MARK: - Power state → refresh mode

    @objc private func systemWillSleep() {
        badgeUpdater?.setMode(.suspended)
    }

    @objc private func systemDidWake() {
        // Wake up with popover hidden → dormant. (If the popover was open when
        // sleeping, the user will click again and togglePopover flips to active.)
        badgeUpdater?.setMode(.dormant)
    }

    @objc private func powerStateChanged() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            badgeUpdater?.setMode(.suspended)
        }
        // Exiting low-power mode does not auto-resume; the next popover toggle
        // or sleep/wake cycle restarts the appropriate mode.
    }
```

- [ ] **Step 5: 验证编译**

Run: `swift build --package-path TokenDashSwift 2>&1 | tail -20`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add TokenDashSwift/Sources/TokenDash/App.swift
git commit -m "Drive BadgeUpdater mode from popover visibility and power notifications"
```

---

## Task 4: 构建、本地热更新、验收

> 项目约定（CLAUDE.md）：每次改完自动重新构建并启动，不让用户手动操作。复用 cerebrum 2026-06-19 记录的「只改 Swift 代码的本地更新捷径」——替换二进制 + add_rpath + 重签 + open，免跑完整 package-app.sh。

**Files:** 无（验证 + 部署）

- [ ] **Step 1: 完整构建 + 测试**

Run: `swift test --package-path TokenDashSwift 2>&1 | tail -15`
Expected: 全部 PASS。

- [ ] **Step 2: 退出当前运行的 TokenDash**

Run: `pkill -x TokenDash 2>/dev/null; sleep 1; echo "stopped"`
Expected: `stopped`（或无输出，若未在运行）。

- [ ] **Step 3: 替换二进制 + 修 rpath + 重签**

Run（一行一行执行，任一失败立即停下排查）：

```bash
cp TokenDashSwift/.build/debug/TokenDash /Applications/TokenDash.app/Contents/MacOS/TokenDash && \
install_name_tool -add_rpath '@executable_path/../Frameworks' /Applications/TokenDash.app/Contents/MacOS/TokenDash 2>/dev/null; \
codesign --force --sign - /Applications/TokenDash.app/Contents/MacOS/TokenDash && \
codesign --force --sign - --deep /Applications/TokenDash.app && \
echo "replaced+signed"
```
Expected: `replaced+signed`。（`install_name_tool` 若 rpath 已存在会非零退出，被 `;` 吞掉，无妨。）

- [ ] **Step 4: 启动新版**

Run: `open /Applications/TokenDash.app && sleep 3 && echo "launched"`
Expected: `launched`，菜单栏出现 TokenDash 图标。

- [ ] **Step 5: 验收 dormant 期 CPU 归零（核心指标）**

人工 + 命令结合：
1. 让 popover 保持关闭 ≥5 分钟（不要点开）。
2. 期间 TokenDash daemon 端口（默认 3456，或 `~/.tokendash/daemon.port`）不应被频繁请求。可抽查看请求频率：

Run: `lsof -i :$(cat ~/.tokendash/daemon.port 2>/dev/null || echo 3456) -nP 2>/dev/null | head -5`
（仅确认 daemon 在监听。CPU 用「活动监视器」观察 TokenDash 与 node 进程，dormant 期平均 CPU 应接近 0、< 0.5%。）

3. 点开 popover：确认 1s 内出现完整数据（hourly/projects/trend/quota 卡片），实时速率图每 ~10s 跳动一次。
4. 关闭 popover：确认速率图停止刷新（不再每 10s 拉）。
5. **回归检查**：badge 数字仍在更新；quota 卡片显示正常；Dashboard 按钮（`http://127.0.0.1:<port>`）可打开；手动点刷新按钮触发一次强刷。

- [ ] **Step 6: 验收 daemon 自愈未受影响**

Run: `pkill -f daemon.cjs 2>/dev/null; sleep 35; ls ~/.tokendash/daemon.pid 2>/dev/null && echo "self-healed" || echo "MISSING"`
Expected: 约 30s 内 `self-healed`（`AppDelegate.checkDaemonHealth` 重启 daemon，BadgeUpdater.updatePort 热切换，模式保持）。

- [ ] **Step 7: 更新 CHANGELOG（如需发版）**

如本次将随版本发布，在 `CHANGELOG.md` 顶部加一条「省电：菜单栏后台改为按需刷新，popover 合上时 CPU 归零」。否则跳过。

- [ ] **Step 8: 收尾 commit（如 Step 7 改了 CHANGELOG）**

```bash
git add CHANGELOG.md
git commit -m "Note energy optimization in changelog"
```

---

## Self-Review（计划作者自查，已做）

- **Spec 覆盖**：
  - 5.1 状态机三态 → Task 2 `RefreshMode` + Task 3 触发。✓
  - 5.2 updateBadge/updateFull 拆分 + refresh:false + 手动强刷 → Task 2 Step 4 + 测试。✓
  - 5.3 daemon 零改动（缓存已存在）→ 已确认 `daily.ts:14`/`api.ts:17`。✓
  - 5.4 daemon 自愈保持 → Task 4 Step 6 验证。✓
  - 5.5 单测 + 手动验收 → Task 2 测试 + Task 4 Step 5。✓
  - 第 6 节决策（脉冲 10s / quota 走缓存仅手动强刷 / dormant 复用用户刷新间隔）→ Task 2 代码。✓
  - 第 8 节验收标准 1-5 → Task 4 Step 5-6。✓
- **占位符扫描**：无 TBD/TODO；所有代码步骤含完整代码。✓
- **类型一致性**：`RefreshMode`、`performBadgeUpdate()`、`performFullUpdate(forceRefresh:forceQuota:)`、`setMode(_:)`、`APIClientProtocol` 在 Task 1-3 与测试间命名一致。✓
- **简化说明**：spec 5.1 写「低电量降级 dormant 到 120s」，本计划简化为「低电量 → suspended」（更省电、实现更简）；若后续需要 120s dormant，可加一个 `.dormantLowPower` 模式。已在 Task 3 Step 4 注释说明。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-03-tokendash-energy-optimization.md`. Two execution options:**

1. **Subagent-Driven (recommended)** — 每个 task 派一个新 subagent，task 间我来 review，迭代快。
2. **Inline Execution** — 在当前会话按 executing-plans 批量执行，带 checkpoint。

**Which approach?**
