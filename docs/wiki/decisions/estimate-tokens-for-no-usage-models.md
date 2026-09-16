---
title: 为不返回 usage 的本地模型估算 token
type: decision
tags: [pi, 本地模型, token估算, usage]
created: 2026-09-17
updated: 2026-09-17
status: active
---

# 为不返回 usage 的本地模型估算 token

## 背景（现状与约束）

pi 的会话以 JSONL 记录在 `~/.pi/agent/sessions/<project-slug>/<timestamp>_<id>.jsonl`。
其中每条 `assistant` 消息带 `usage`（`input/output/totalTokens/cost`）。但**本地模型**
（如经 amax 代理的 `qwen-3.8-27B`）流式响应**不返回 usage**，`totalTokens` 恒为 0；
只有云端模型（如 `deepseek-flash`）才有真实 usage。

旧版 `piParser` 直接 `if (totalTokens === 0) continue`，导致本地模型会话被整体丢弃——
实测一个真实会话里 `qwen-3.8-27B` 557 条 assistant 消息全部 `totalTokens=0`，而
`deepseek-flash` 310 条都有真实值。结果仪表盘上本地模型的用量完全不显示。

约束：
- 无法改动 pi 端让它返回 usage（第三方 harness）。
- 估算值必须与真实值可区分，避免污染成本/趋势判断。
- 不能重复计数（真实 usage 已含上下文回放，估算不能在其之上再叠加）。

## 备选方案

1. **只统计有 usage 的消息**（现状）：简单，但本地模型数据全丢，用户主诉。
2. **按消息内容估算**：对 `totalTokens=0` 的消息，用文本长度推 token。能补上数据，
   但需处理上下文累积、压缩回落、与真实 usage 的衔接。
3. **固定系数近似**（如按行数/字数统一乘系数）：实现最简单，但对中文/代码/工具调用
   差异大，误差高。

## 决策（选定方案）

采用方案 2（内容估算）并细化：

- **基线上下文**：pi 的 system prompt + 工具 schema 不在 JSONL 里，但每轮请求都携带，
  按典型 pi 会话体量取 `BASELINE_CONTEXT_TOKENS = 4000` 打底。
- **逐条累积**：`user`/`toolResult`/`assistant` 的内容 token 逐条累加进当前上下文；
  中文按 ≈1 token/字，英文/代码按 ≈3.5 字符/token（`estimateTokens`）。
- **零 usage 消息**：有实际输出才记录为「估算」事件（`estimated: true`），
  `input=当前上下文`、`output=本条内容`；空内容（如 aborted）不记录。
- **真实 usage 重锚定**：出现真实 usage 时按上报值统计（`estimated: false`），
  并把它作为后续估算的上下文锚点（`input>0 ? input : 上下文` + output），避免估算漂移。
- **压缩回落**：`compaction` 后上下文回落为 `基线 + summary 估算`。
- **可区分标记**：新增 `estimatedTokens` 字段贯穿 `ModelBreakdown/DailyEntry/Totals`，
  前端对含估算的总量显示 `≈` 与「estimated」提示，与真实值分开呈现。

## 理由（决策依据）

- 用户主诉就是本地模型数据缺失，必须补上（否掉方案 1）。
- 内容估算比固定系数更贴近真实分布（中文 vs 代码），且能随上下文/压缩/模型切换自适应。
- 「估算/真实」分离是核心：本地模型无成本、无精确量，混入真实值会误导成本与配额判断，
  故单独标记并在 UI 明示。
- 用真实 usage 重锚定，保证混用本地+云端的长会话里估算不会持续漂移。

## 后果（影响与后续）

- 所有 parser（claude/codex/openclaw/opencode/pi）的 `DailyEntry/ModelBreakdown/Totals`
  统一新增 `estimatedTokens`（非 pi 恒为 0），`schemas.ts` 加 `default(0)` 保证兼容。
- `piParser` 索引版本升到 `pi-session-v4-1min` 触发缓存重建。
- 估算值只是量级参考，**不等于真实 token**；成本仍按真实 usage 计（本地模型 cost=0）。
- 若将来 pi 端能返回本地模型 usage，应优先用真实值、把估算作为兜底。
- 前端 `Dashboard` 的 KPI 与每日表格对含估算的条目加 `≈` 与 tooltip。

## 关联

- 模块：[pi 解析器](../entities/pi-parser.md)
- 排查记录：[Windows 终端 Ctrl+C 退出乱码（代码页）](../queries/windows-ctrlc-utf8-gbk-garbled.md)
