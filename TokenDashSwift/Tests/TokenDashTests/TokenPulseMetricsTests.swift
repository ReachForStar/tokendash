import XCTest
@testable import TokenDash

final class TokenPulseMetricsTests: XCTestCase {
    func testSeparatesNowStageAndWindowRates() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let samples = [
            sample(at: start, delta: 0, rate: 0),
            sample(at: start.addingTimeInterval(5), delta: 1_000, rate: 200),
            sample(at: start.addingTimeInterval(10), delta: 0, rate: 0),
        ]

        let metrics = TokenPulseMetrics(samples: samples)

        XCTAssertEqual(metrics.nowRate, 0)
        XCTAssertEqual(metrics.stageAverageRate, 100, accuracy: 0.001)
        XCTAssertEqual(metrics.windowAverageRate, 1_000 / 15, accuracy: 0.001)
        XCTAssertTrue(metrics.isStageActive)
    }

    func testStartsNewStageAfterTwoMinuteGap() {
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        let samples = [
            sample(at: start, delta: 1_000, rate: 200),
            sample(at: start.addingTimeInterval(180), delta: 600, rate: 120),
            sample(at: start.addingTimeInterval(185), delta: 0, rate: 0),
        ]

        let metrics = TokenPulseMetrics(samples: samples)

        XCTAssertEqual(metrics.stageAverageRate, 60, accuracy: 0.001)
        XCTAssertTrue(metrics.isStageActive)
    }

    func testStageBecomesIdleAfterGracePeriod() {
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        let samples = [
            sample(at: start, delta: 1_000, rate: 200),
            sample(at: start.addingTimeInterval(301), delta: 0, rate: 0),
        ]

        XCTAssertFalse(TokenPulseMetrics(samples: samples).isStageActive)
    }

    func testLegacyPersistedSampleDefaultsMissingInputAndOutputToZero() throws {
        let json = """
        {"timestamp":1000,"tokenDelta":500,"tokensPerSecond":100}
        """

        let sample = try JSONDecoder().decode(TokenPulseSample.self, from: Data(json.utf8))

        XCTAssertEqual(sample.inputDelta, 0)
        XCTAssertEqual(sample.outputDelta, 0)
        XCTAssertEqual(sample.inputTokensPerSecond, 0)
        XCTAssertEqual(sample.outputTokensPerSecond, 0)
    }

    private func sample(at timestamp: Date, delta: Int, rate: Double) -> TokenPulseSample {
        TokenPulseSample(timestamp: timestamp, tokenDelta: delta, tokensPerSecond: rate)
    }
}
