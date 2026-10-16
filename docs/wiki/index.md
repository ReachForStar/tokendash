---
type: index
updated: 2026-10-16
---

# Wiki 索引

> 人工/Agent 显式查阅用的完整目录；会话中的导航由 wiki-memory hook 注入的目录树提供。
> 格式：`[页面标题](相对路径) — 一行摘要`。

## 实体 entities

- [模型计费与币种](entities/model-pricing.md) — 模型名称匹配、Go 主价格、AMAX 补充和设置汇率
- [所有 Agent 汇总](entities/all-agents-dashboard.md) — 复用主仪表盘，累加用量并合并同名项目
- [会话内容与分析](entities/session-transcripts.md) — OpenCode、Pi 的真实消息、工具和 Skill 事件

- [仪表盘设置入口](entities/dashboard-settings.md) — 齿轮按钮与 Codex 数据源配置弹窗

- [pi 解析器（piParser）](entities/pi-parser.md) — 解析 pi 会话 JSONL，支持本地模型 token 估算

## 概念 concepts

## 源总结 sources

## 决策 decisions

- [为不返回 usage 的本地模型估算 token](decisions/estimate-tokens-for-no-usage-models.md) — ADR：基线上下文+内容估算+真实 usage 重锚定，用 estimatedTokens 区分真实/估算

## 查询沉淀 queries

- [汇总计费与会话验收](queries/agent-currency-pricing-verification.md) — 旧后端接口修复及真实数据验收

- [Windows 终端 Ctrl+C 退出乱码（代码页 936/GBK）](queries/windows-ctrlc-utf8-gbk-garbled.md) — npm run dev 退出乱码根因是控制台代码页 936，解法 chcp 65001 + UTF-8
