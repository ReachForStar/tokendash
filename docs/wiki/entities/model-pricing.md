---
title: 模型计费与币种
type: entity
tags: [计费, 汇率, AMAX, OpenCode]
created: 2026-10-16
updated: 2026-10-16
status: active
---

# 模型计费与币种

## 职责

按模型名称计算用量价值，忽略供应商。基础费用使用美元，界面可显示美元或人民币。用量价值不是订阅账单。

## 关键文件与接口

- `src/shared/modelPricing.ts`：共享价格、模型名称规范化、上下文分级与 DeepSeek 高峰时间判断。
- `src/shared/amaxPricing.json`：2026-10-16 从 AMAX 公开价格接口提取的人民币参考价格；包含 77 个可识别的按 token 计费条目，不含账号信息或密钥。
- `scripts/update-amax-pricing.mjs`：从公开接口更新参考价格，使用现有 TypeScript 语法分析库识别简单分级表达式；输出跳过列表，不执行远端表达式。命令为 `node scripts/update-amax-pricing.mjs`。
- `src/server/appSettings.ts`、`PUT /api/settings/billing`：持久化汇率，校验正数与有限值。
- `src/client/hooks/useCurrency.tsx`：币种显示；人民币金额等于美元金额乘设置汇率。

## 上下游依赖

1. OpenCode Go 已配置模型优先使用 [Go 价格表](https://opencode.ai/v2/docs/console/go/)。
2. 已配置的 Claude 模型使用 [Anthropic 价格表](https://platform.claude.com/docs/en/about-claude/pricing)，其他已有 GPT 参考价保留项目配置。
3. 缺失模型使用 [AMAX 模型页](https://ai.amaxsmp.com/models)对应公开 `/api/pricing` 数据。按用户确认的 `1 ⚡ = 1 人民币` 保存原始价格，除以服务端设置汇率换算美元。
4. 不使用供应商、线路和账号折扣匹配模型。忽略大小写、供应商路径前缀和日期后缀，保留模型版本差异。
5. 未识别价格或缺失缓存单价时，不套用 Sonnet 价格。有原始费用时保留，否则不计价；界面提示合计可能不完整。

AMAX `/v1/models` 只提供模型目录。鉴权验收返回 96 个模型，价格另取公开接口。密钥不进入仓库。AMAX 的复杂时间或多层表达式未自动提取；未识别项保持未配置。

## 重要变更记录

- 2026-10-16：修正 GLM-5.2、Opus 4.6、Haiku 4.5 计费。Go 的 GLM-5.2 输入、输出、缓存读取价分别为每百万 token 1.40、4.40、0.26 美元。
- 汇率保存会清除接口缓存；解析索引、会话索引、OpenCode 事件缓存及 Codex 工作线程结果均区分汇率。Codex 按请求计算价格，避免先累计上下文再误判分级。
- 当前实际保存汇率为 6.68。价格规则单元测试、服务端保存和重新读取已通过；完整回归结果见[验收记录](../queries/agent-currency-pricing-verification.md)。

## 关联页面

- [仪表盘设置入口](dashboard-settings.md)
- [所有 Agent 汇总](all-agents-dashboard.md)
- [会话内容与分析](session-transcripts.md)
