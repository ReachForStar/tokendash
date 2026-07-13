import Foundation
import XCTest
@testable import TokenDash

@MainActor
final class DaemonManagerLifecycleTests: XCTestCase {
    func testStartDaemonTerminatesSpawnedProcessWhenReadinessTimesOut() async throws {
        let process = FakeDaemonProcess()
        let dataDir = temporaryDataDir()
        let manager = DaemonManager(
            dataDir: dataDir.path,
            nodeFinder: { URL(fileURLWithPath: "/usr/bin/node") },
            daemonScriptFinder: { "/tmp/daemon.cjs" },
            processFactory: { process },
            probe: { _ in .unavailableOrForeign },
            startupTimeout: 0.01,
            pollIntervalNanoseconds: 1_000_000
        )

        do {
            _ = try await manager.startDaemon()
            XCTFail("startDaemon should time out when readiness probe never succeeds")
        } catch DaemonError.timeout {
            // expected
        }

        XCTAssertEqual(process.runCount, 1)
        XCTAssertEqual(process.terminateCount, 1, "timeout must terminate the daemon started by this attempt")
        XCTAssertFalse(process.isRunning)
        XCTAssertNil(manager.port)
        XCTAssertFalse(manager.isRunning)
    }

    func testStartDaemonReusesCompatibleDaemonDiscoveredOnFallbackPort() async throws {
        let process = FakeDaemonProcess()
        let dataDir = temporaryDataDir()
        let manager = DaemonManager(
            dataDir: dataDir.path,
            nodeFinder: { URL(fileURLWithPath: "/usr/bin/node") },
            daemonScriptFinder: { "/tmp/daemon.cjs" },
            processFactory: { process },
            probe: { port in port == 3457 ? .compatible : .unavailableOrForeign },
            startupTimeout: 0.01,
            pollIntervalNanoseconds: 1_000_000,
            discoveryPorts: [3456, 3457, 3458]
        )

        let port = try await manager.startDaemon()

        XCTAssertEqual(port, 3457)
        XCTAssertEqual(process.runCount, 0, "compatible existing TokenDash daemon should be reused instead of spawning another fallback daemon")
        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(manager.port, 3457)
    }

    private func temporaryDataDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokendash-daemon-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class FakeDaemonProcess: DaemonProcess {
    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardOutput: Any?
    var standardError: Any?
    private(set) var isRunning = false
    private(set) var runCount = 0
    private(set) var terminateCount = 0
    private(set) var interruptCount = 0

    func run() throws {
        runCount += 1
        isRunning = true
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }

    func interrupt() {
        interruptCount += 1
        isRunning = false
    }
}
