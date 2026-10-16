---
title: 会话内容与分析
type: entity
tags: [OpenCode, Pi, 会话, 工具, Skill]
created: 2026-10-16
updated: 2026-10-16
status: active
---

# 会话内容与分析

## 职责

从真实消息构建用户请求、模型调用、回复、工具调用、工具结果和 Skill 事件，供原有 Sessions 页面显示。

## 关键文件与接口

- `src/server/sessionTranscripts.ts`：只读解析 OpenCode SQLite 与 Pi JSONL。
- `src/server/sessionAnalyticsParser.ts`：规范化事件、汇总趋势、列表和单会话详情。
- `src/server/analyticsParser.ts`：从结构化 Edit／Write 参数统计增删行；不推测 shell 命令实际产生的文件变化。
- `src/server/routes/analytics.ts`：OpenCode、Pi 使用真实工具事件，取代固定空响应。
- `src/client/components/SessionAnalyticsSection.tsx`：复用现有任务详情布局，无实际事件时隐藏对应图表或指标。

## 上下游依赖

OpenCode 新版消息位于 `session_message`，关联 `session_v2.directory`。用户正文位于 `data.text`；模型正文及工具位于 `data.content`；工具输入和结果位于 `state.input`、`state.content`。旧版 message／part 表通过 SQLite 库读取。

Pi 消息的 `role` 包括 system、user、assistant、toolResult；assistant 的 content 包含 text、thinking、toolCall。通过 callId 将结果关联到调用。读取 SKILL.md 产生的 Skill 使用明确标注为推断，不伪装成原生 Skill 调用。

详情只在 `include=content` 时返回经脱敏的正文，长正文按既有边界截断并标明。聚合接口不返回完整正文。错误和中断状态来自原始消息。

## 重要变更记录

- 2026-10-16：修复只保留 Token 摘要且 `events: []` 的问题。补充 OpenCode 用户消息 `data.text` 及 Pi 系统／工具消息。
- 真实数据验收：OpenCode 5 个会话、3359 次 LLM 调用、3534 次工具调用；Pi 41 个会话、6331 次 LLM 调用、6580 次工具调用。数字为验收快照，会随会话变化。
- `tests/verify-live-sessions.ts` 已验证两种来源都有用户请求、回复和工具结果正文，汇总 Sessions 有 204 个会话，且可打开来源详情。
- `Avg daily changes` 只在存在真实增删行时显示；LLM、工具与 Skill 图表无实际数据时隐藏。

## 关联页面

- [所有 Agent 汇总](all-agents-dashboard.md)
- [pi 解析器](pi-parser.md)
- [模型计费与币种](model-pricing.md)

## 页面职责边界

Sessions 负责会话搜索、模型和状态筛选、分页、自动刷新以及完整消息和工具详情。时间与项目筛选复用主仪表盘入口。Token 和费用总览复用 Tokens／Cost 页面，不在 Sessions 另建汇总卡片。单个会话详情保留 Token，供核对该会话记录。调用次数、工具成功率、时长和 Skill 属于会话行为分析；仅在有实际数据时显示。
