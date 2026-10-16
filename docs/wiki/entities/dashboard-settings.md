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

仪表盘顶部的齿轮按钮打开 Codex 数据源设置。

## 关键文件与接口

- `src/client/components/Dashboard.tsx`：`renderSettingsButton` 绘制齿轮，保留按钮提示和无障碍名称 `Configure Codex data sources`。
- `src/client/components/CodexDataSourcesSettings.tsx`：显示数据源配置弹窗。

## 上下游依赖

按钮通过 `showDataSourceSettings` 控制弹窗显示。图标使用内联 SVG，无新增依赖。

## 重要变更记录

- 2026-10-16：将放射线图标替换为齿轮。203 项单元测试通过；在本地浏览器验证齿轮外观、打开弹窗和关闭弹窗。

## 关联页面

- [知识库索引](../index.md)
