import Foundation

/// Separates the latest accounting update from the averages that better
/// describe sustained work. Provider logs usually publish usage at response
/// boundaries, so a zero NOW value does not imply that a stream has stopped.
struct TokenPulseMetrics {
    let nowRate: Double
    let stageAverageRate: Double
    let windowAverageRate: Double
    let isStageActive: Bool

    static let empty = TokenPulseMetrics(
        nowRate: 0,
        stageAverageRate: 0,
        windowAverageRate: 0,
        isStageActive: false
    )

    init(samples: [TokenPulseSample]) {
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        guard let first = ordered.first, let last = ordered.last else {
            self = .empty
            return
        }

        nowRate = max(0, last.tokensPerSecond)

        let totalTokens = ordered.reduce(0) { $0 + max(0, $1.tokenDelta) }
        let coveredSeconds = max(5, last.timestamp.timeIntervalSince(first.timestamp) + 5)
        windowAverageRate = Double(totalTokens) / coveredSeconds

        let positive = ordered.filter { $0.tokenDelta > 0 }
        guard let latestPositive = positive.last else {
            stageAverageRate = 0
            isStageActive = false
            return
        }

        // A two-minute gap between accounted responses starts a new stage.
        // Keep that stage visible for up to five minutes so a long streaming
        // response is not misrepresented as an immediate stop.
        let stageGap: TimeInterval = 2 * 60
        let activeGracePeriod: TimeInterval = 5 * 60
        var stageStart = latestPositive

        for sample in positive.dropLast().reversed() {
            if stageStart.timestamp.timeIntervalSince(sample.timestamp) > stageGap {
                break
            }
            stageStart = sample
        }

        let stageSamples = ordered.filter { $0.timestamp >= stageStart.timestamp }
        let stageTokens = stageSamples.reduce(0) { $0 + max(0, $1.tokenDelta) }
        let stageSeconds = max(5, last.timestamp.timeIntervalSince(stageStart.timestamp) + 5)
        stageAverageRate = Double(stageTokens) / stageSeconds
        isStageActive = last.timestamp.timeIntervalSince(latestPositive.timestamp) <= activeGracePeriod
    }

    private init(
        nowRate: Double,
        stageAverageRate: Double,
        windowAverageRate: Double,
        isStageActive: Bool
    ) {
        self.nowRate = nowRate
        self.stageAverageRate = stageAverageRate
        self.windowAverageRate = windowAverageRate
        self.isStageActive = isStageActive
    }
}

/// Trailing-window smoothed token rates, one per sample (sorted ascending by
/// timestamp, same length as the input). Each output point = Σ token deltas
/// over samples in `[tᵢ − window, tᵢ]` ÷ `window`.
///
/// Using a delta-sum (rather than averaging the per-sample instantaneous rates)
/// is the key to killing the 0↔spike jitter on the pulse chart: a response that
/// lands in one 10s bucket is correctly attributed across the whole trailing
/// window instead of showing up as a single needle. `window` is the divisor
/// (clamped to ≥ 5s), so a partial window at the chart's leading edge reads as
/// "past N seconds average including idle time", not an amplified instantaneous.
func pulseSmoothedRates(
    for samples: [TokenPulseSample],
    window: TimeInterval
) -> [(input: Double, output: Double)] {
    let ordered = samples.sorted { $0.timestamp < $1.timestamp }
    let safeWindow = max(5, window)
    return ordered.map { sample in
        let windowStart = sample.timestamp.addingTimeInterval(-safeWindow)
        let inWindow = ordered.filter { $0.timestamp >= windowStart && $0.timestamp <= sample.timestamp }
        let inputSum = inWindow.reduce(0.0) { $0 + Double(max(0, $1.inputDelta)) }
        let outputSum = inWindow.reduce(0.0) { $0 + Double(max(0, $1.outputDelta)) }
        return (input: inputSum / safeWindow, output: outputSum / safeWindow)
    }
}
