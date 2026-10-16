---
type: index
updated: 2026-10-16
---

# Wiki 索引

> 人工/Agent 显式查阅用的完整目录；会话中的导航由 wiki-memory hook 注入的目录树提供。
> 格式：`[页面标题](相对路径) — 一行摘要`。

## 实体 entities

- [仪表盘设置入口](entities/dashboard-settings.md) — 齿轮按钮与 Codex 数据源配置弹窗

- [pi 解析器（piParser）](entities/pi-parser.md) — 解析 pi 会话 JSONL，支持本地模型 token 估算

## 概念 concepts

## 源总结 sources

## 决策 decisions

- [为不返回 usage 的本地模型估算 token](decisions/estimate-tokens-for-no-usage-models.md) — ADR：基线上下文+内容估算+真实 usage 重锚定，用 estimatedTokens 区分真实/估算

## 查询沉淀 queries

- [Windows 终端 Ctrl+C 退出乱码（代码页 936/GBK）](queries/windows-ctrlc-utf8-gbk-garbled.md) — npm run dev 退出乱码根因是控制台代码页 936，解法 chcp 65001 + UTF-8
