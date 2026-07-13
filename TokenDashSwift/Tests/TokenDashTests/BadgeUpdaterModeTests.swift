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
        // Detail state paints synchronously; quota refreshes async — give the
        // detached quota task a moment to run before asserting on it.
        try await Task.sleep(nanoseconds: 200_000_000)  // 0.2s

        let counts = await mock.snapshot()
        XCTAssertGreaterThan(counts.daily, 0)
        XCTAssertGreaterThan(counts.blocks, 0)
        XCTAssertGreaterThan(counts.projects, 0)
        XCTAssertGreaterThan(counts.quota, 0, "active 详情刷新最终要拉 quota（异步）")
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
        XCTAssertNotNil(state.lastUpdatedAt, "手动刷新完成后必须记录最近刷新时间")
        XCTAssertFalse(state.isRefreshing, "手动刷新完成后必须退出 loading 状态")
    }

    func testPopoverRefreshIsThrottledForThirtyMinutes() async throws {
        let state = AppState()
        let mock = MockAPIClient()
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
        let updater = BadgeUpdater(
            state: state,
            client: mock,
            now: { now },
            popoverRefreshInterval: 30 * 60
        )

        let refreshedInitially = await updater.refreshOnPopoverOpenIfNeeded()
        XCTAssertTrue(refreshedInitially)
        let firstCounts = await mock.snapshot()
        XCTAssertGreaterThan(firstCounts.daily, 0)
        let firstDailyRefresh = await mock.lastDailyRefresh
        XCTAssertEqual(firstDailyRefresh, true)

        now.addTimeInterval(29 * 60 + 59)
        let refreshedBeforeInterval = await updater.refreshOnPopoverOpenIfNeeded()
        XCTAssertFalse(refreshedBeforeInterval)
        let throttledCounts = await mock.snapshot()
        XCTAssertEqual(throttledCounts.daily, firstCounts.daily)

        now.addTimeInterval(2)
        let refreshedAfterInterval = await updater.refreshOnPopoverOpenIfNeeded()
        XCTAssertTrue(refreshedAfterInterval)
        let finalCounts = await mock.snapshot()
        XCTAssertGreaterThan(finalCounts.daily, firstCounts.daily)
    }

    func testBackgroundRefreshForceRefreshesDetailsAndQuota() async throws {
        let state = AppState()
        let mock = MockAPIClient()
        let updater = BadgeUpdater(state: state, client: mock)

        await updater.performBackgroundRefresh()

        let lastDailyRefresh = await mock.lastDailyRefresh
        let lastQuotaRefresh = await mock.lastQuotaRefresh
        XCTAssertEqual(lastDailyRefresh, true, "每小时后台刷新必须绕过详情缓存")
        XCTAssertEqual(lastQuotaRefresh, true, "每小时后台刷新必须绕过 quota 缓存")
        XCTAssertNotNil(state.lastUpdatedAt)
        XCTAssertFalse(state.isRefreshing)
    }
}

/// 计数型 mock — 记录每个端点被调用的次数与关键参数，供模式断言。
actor MockAPIClient: APIClientProtocol {
    private(set) var agents = 0
    private(set) var daily = 0
    private(set) var blocks = 0
    private(set) var projects = 0
    private(set) var quota = 0
    private(set) var lastQuotaRefresh: Bool? = nil
    private(set) var lastDailyRefresh: Bool? = nil

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
        lastDailyRefresh = refresh
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
