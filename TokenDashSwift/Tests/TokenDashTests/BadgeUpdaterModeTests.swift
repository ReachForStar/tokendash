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
