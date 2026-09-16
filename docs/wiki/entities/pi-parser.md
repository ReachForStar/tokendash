---
title: pi 解析器（piParser）
type: entity
tags: [pi, parser, 模块]
created: 2026-09-17
updated: 2026-09-17
status: active
---

# pi 解析器（piParser）

## 职责

解析 pi harness 的会话 JSONL，聚合出 daily / projects / blocks 三类用量响应。
支持本地模型（不返回 usage）的 token 估算，并用 `estimatedTokens` 与真实值区分。

## 数据来源

- 会话目录：`~/.pi/agent/sessions/<project-slug>/<timestamp>_<id>.jsonl`
  （`getPiSessionsDir()`）。
- 每行一条事件：`session` / `model_change` / `message`（user/assistant/toolResult）/
  `compaction` 等。
- 本地模型（amax 代理的 `qwen-3.8-27B` 等）`message.usage.totalTokens` 恒为 0；
  云端模型（`deepseek-flash` 等）带真实 usage。

## 关键文件/接口

- `src/server/piParser.ts`（约 564 行）
- 导出：`isPiAccessible()`、`scanPiSessions()`、`parsePiSession()`、
  `buildDailyFromSessions()`（纯函数，便于单测注入 fixture）、
  `getDailyResponse()`、`getProjectsResponse()`、`getBlocksResponse()`。
- 常量：`PI_INDEX_VERSION = 'pi-session-v4-1min'`（缓存版本，改动解析逻辑需升版）、
  `BASELINE_CONTEXT_TOKENS = 4000`、`IMAGE_TOKEN_ESTIMATE = 1000`、`DEFAULT_TZ = 'Asia/Shanghai'`。
- 核心类型：`PiTokenEvent`（含 `estimated` 标记）、`PiSession`、`TokenAccumulator`
  （含 `estimatedTokens`）。
- 估算：`estimateTokens()`（CJK≈1 token/字，其他≈3.5 字符/token）、
  `estimateContentTokens()`（统一处理 string / part 数组）。

## 上下游依赖

- 上游：pi 会话文件（只读）。
- 下游：路由 `routes/daily.ts`/`projects.ts`/`blocks.ts`（agent 分发），
  共享 `src/shared/types.ts`、`src/shared/schemas.ts`（`estimatedTokens` 字段）。
- 前端：`Dashboard.tsx` 对含估算的条目显示 `≈` 与 estimated 提示。

## 重要变更记录

- 2026-09-17：为不返回 usage 的本地模型加入 token 估算（基线上下文 + 逐条累积 +
  真实 usage 重锚定 + compaction 回落），新增 `estimatedTokens` 贯穿各聚合层；
  索引版本升到 `pi-session-v4-1min`。见 [决策页](../decisions/estimate-tokens-for-no-usage-models.md)。

## 待确认

- 估算系数（4000 基线、3.5 字符/token）是经验值，后续可按真实 usage 校准。
