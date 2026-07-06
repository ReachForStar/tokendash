import XCTest
@testable import TokenDash

final class PulseSmoothedRatesTests: XCTestCase {
    private func sample(_ t: TimeInterval, input: Int, output: Int) -> TokenPulseSample {
        TokenPulseSample(
            timestamp: Date(timeIntervalSinceReferenceDate: t),
            tokenDelta: input + output,
            tokensPerSecond: 0,
            inputDelta: input,
            outputDelta: output
        )
    }

    func testEmptyReturnsEmpty() {
        XCTAssertEqual(pulseSmoothedRates(for: [], window: 30).count, 0)
    }

    func testSingleSampleAveragesOverWindow() {
        // one sample, delta 300 spread over the 30s window -> 10/s
        let rates = pulseSmoothedRates(for: [sample(100, input: 300, output: 0)], window: 30)
        XCTAssertEqual(rates.count, 1)
        XCTAssertEqual(rates[0].input, 10, accuracy: 0.001)
        XCTAssertEqual(rates[0].output, 0, accuracy: 0.001)
    }

    func testTrailingWindowSumsDeltas() {
        // 3 samples at t=0,10,20 (each input 300). window=30s.
        let samples = [
            sample(0, input: 300, output: 0),
            sample(10, input: 300, output: 0),
            sample(20, input: 300, output: 0),
        ]
        let rates = pulseSmoothedRates(for: samples, window: 30)
        // t=0:  only sample 0 (300) in [-30,0]  -> 10/s
        XCTAssertEqual(rates[0].input, 10, accuracy: 0.001)
        // t=10: samples 0+1 (600) in [-20,10]  -> 20/s
        XCTAssertEqual(rates[1].input, 20, accuracy: 0.001)
        // t=20: samples 0+1+2 (900) in [-10,20] -> 30/s
        XCTAssertEqual(rates[2].input, 30, accuracy: 0.001)
    }

    func testSpikeAttributedAcrossWindowNotOneNeedle() {
        // A single big response (delta 3000) at t=0 must raise the rate for
        // every point within 30s after it, then drop to 0 — not vanish into a
        // one-sample needle.
        var samples: [TokenPulseSample] = [sample(0, input: 3000, output: 0)]
        for t in stride(from: 10.0, through: 60.0, by: 10.0) {
            samples.append(sample(t, input: 0, output: 0))
        }
        let rates = pulseSmoothedRates(for: samples, window: 30)
        // t=0:  3000/30 = 100
        XCTAssertEqual(rates[0].input, 100, accuracy: 0.001)
        // t=30 (index 3): t=0 still inside [0,30] -> 100
        XCTAssertEqual(rates[3].input, 100, accuracy: 0.001)
        // t=40 (index 4): t=0 now outside [10,40] -> 0
        XCTAssertEqual(rates[4].input, 0, accuracy: 0.001)
    }

    func testClampsUndersizedWindow() {
        // window <= 0 is clamped to 5s so we never divide by ~0.
        let rates = pulseSmoothedRates(for: [sample(0, input: 50, output: 0)], window: 0)
        XCTAssertEqual(rates[0].input, 10, accuracy: 0.001) // 50 / max(5, 0) = 10
    }
}
