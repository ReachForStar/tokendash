# Pulse Chart 平滑（trailing 30s 速率）

- **日期**: 2026-07-03
- **状态**: Draft（待用户审核）
- **范围**: `HourlyChartView.swift` 的 Pulse 折线平滑
- **作者**: brainstorming 会话产出

## 1. 背景

脉冲折线（Pulse tab）画的 y 值是每个采样点的**瞬时** input/output 速率（`inputTokensPerSecond = 10s 窗口 token delta / 10s`，见 `HourlyChartView.swift:551-554`）。因 JSONL 在**响应结束时才批量写入** token，10s 采样窗口要么恰好抓到一次响应结束（大 delta → 尖峰），要么没抓到（delta=0），瞬时速率在 0/尖峰间反复跳，折线尖刺、忽上忽下。

header 的「STAGE AVG」数字已用 `stageAverageRate`（跨阶段平均）平滑，但**折线没**——所以"数字稳、曲线尖"。Catmull-Rom 只平滑线，平滑不了数据抖。

## 2. 方案

**trailing 30s 窗口速率**：每个折线点 = 过去 30s 内所有 sample 的 `tokenDelta` 求和 ÷ 30s。

- 用 delta 求和（不是"平均瞬时速率"），正确归因跨采样窗口的 token——不会因响应刚好落在哪个 10s 窗口而丢峰或重复计。
- 30s ≈ 3 个采样点（10s 间隔），平衡平滑与实时；停止后约 30s 回落到 0。
- 用户选定（"更实时"取向）。

## 3. 实现（仅 `HourlyChartView.swift`）

1. **抽纯函数** `smoothedRates(for samples: [TokenPulseSample], window: TimeInterval) -> [(input: Double, output: Double)]`：
   - 对每个 sample `i`，取时间在 `[tᵢ − window, tᵢ]` 内的所有 sample，`Σ inputDelta` / `Σ outputDelta`，除以 `max(5, tᵢ − t_最早)`（窗口不足时按实际覆盖时长，避免除以过小值放大噪声）。
   - 顶部常量 `private let pulseSmoothWindow: TimeInterval = 30`。

2. **`PulseLayout`**：用 smoothed rate 算 `inputPoints`/`outputPoints`（log1p 归一化不变）；`sharedPeakRate` 改用 smoothed rate 的 max（峰值随之降低，归一化一致）。

3. **tooltip**：显示该点 smoothed rate（与折线一致），不再显示瞬时抖动值。

4. **不动**：
   - 右端脉动「活跃指示点」：仍用 `samples.last` 瞬时值定颜色 + 脉动（保留实时感）。
   - header「STAGE AVG」：仍用 `stageAverageRate`。
   - 采样逻辑（`BadgeUpdater.samplePulse`）：不变。

## 4. 测试

- `smoothedRates` 单测（XCTest，放 `Tests/TokenDashTests/`）：窗口满（3 点求和）、窗口不足（首个 sample 仅自身）、全零、跨窗口 token 归因（一个大 delta 只算进它之后 30s 内的点）。
- 手动：曲线连贯不尖刺；停止生成后约 30s 回落。

## 5. 验收

1. 折线连贯平滑，无瞬时尖刺（0↔尖峰跳变消失）。
2. header STAGE AVG、活跃指示点脉动行为不变。
3. tooltip 显示平滑值，hover 各点速率与折线视觉一致。
4. 现有 `TokenPulseMetricsTests` 不回归。

## 6. 范围

**In scope**：`HourlyChartView.swift`（PulseLayout + drawPulse tooltip + 抽函数）、新单测。

**Out of scope**：采样频率/窗口可配置化（本次固定 30s 常量）、header 设计改动。
