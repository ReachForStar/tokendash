---
title: 所有 Agent 汇总
type: entity
tags: [Dashboard, 汇总, 项目]
created: 2026-10-16
updated: 2026-10-16
status: active
---

# 所有 Agent 汇总

## 职责

Agent 菜单的“所有 Agent”复用主仪表盘。Token、费用和模型用量逐来源累加，同一天合并一条记录，活跃天数按日期去重。

## 关键文件与接口

- `src/client/api/client.ts`：并行读取各真实来源的 daily、projects、blocks、analytics 接口，汇总后交给原有图表。
- `src/client/utils/agentAggregation.ts`：合并日期、模型、项目与工具统计。
- `src/shared/projectNames.ts`：使用目录末段作为项目名称；同名项目跨 Agent 合并，不增加 Agent 前缀。不同目录下的同名项目也会合并，这是本次用户确定的名称口径。
- `src/server/sessionAnalyticsParser.ts`：`agent=all` 合并会话列表、趋势和分布；内部保留来源与原始会话 ID，用于打开正确详情。

## 上下游依赖

复用 Dashboard 的时间范围、项目、Tokens／Cost／Sessions 和币种控制。项目筛选会映射到每个来源的真实目录。读取失败明确报错，不把失败来源当成零用量。

不同来源可以记录同一次实际请求。汇总按来源记录累加，不推测跨客户端重复会话并删除数据。

## 重要变更记录

- 2026-10-16：根据用户确认，将独立统计弹窗改为主仪表盘选项；项目按名称合并。
- 真实接口验收脚本为 `tests/verify-live-dashboard.ts`，校验总量、逐日累加、同名项目合并和无效汇率拒绝。完整验收见[验收记录](../queries/agent-currency-pricing-verification.md)。

## 关联页面

- [模型计费与币种](model-pricing.md)
- [会话内容与分析](session-transcripts.md)
- [仪表盘设置入口](dashboard-settings.md)
