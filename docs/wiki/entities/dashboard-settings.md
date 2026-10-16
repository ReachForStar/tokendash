---
title: 仪表盘设置入口
type: entity
tags: [Dashboard, 设置]
created: 2026-10-16
updated: 2026-10-16
status: active
---

# 仪表盘设置入口

## 职责

仪表盘顶部仅保留一个齿轮设置按钮，统一配置币种、人民币汇率与 Codex 数据源。筛选栏保留人民币／美元快捷切换，不再提供第二个汇率齿轮。

## 关键文件与接口

- `src/client/components/Dashboard.tsx`：`renderSettingsButton` 绘制齿轮，按钮提示与无障碍名称均为“设置”。
- `src/client/components/CodexDataSourcesSettings.tsx`：显示数据源配置弹窗。

## 上下游依赖

按钮通过 `showDataSourceSettings` 控制弹窗显示。图标使用内联 SVG，无新增依赖。

币种保存在当前浏览器；汇率通过 `PUT /api/settings/billing` 保存到服务端设置。保存后重新读取来源，确保 AMAX 人民币价格使用新汇率。

## 重要变更记录

- 2026-10-16：将放射线图标替换为齿轮。203 项单元测试通过；在本地浏览器验证齿轮外观、打开弹窗和关闭弹窗。
- 2026-10-16：合并两个设置入口；新增币种和汇率，实际保存并重新读取 6.68。

## 关联页面

- [知识库索引](../index.md)
- [模型计费与币种](model-pricing.md)
- [所有 Agent 汇总](all-agents-dashboard.md)
- [验收记录](../queries/agent-currency-pricing-verification.md)
