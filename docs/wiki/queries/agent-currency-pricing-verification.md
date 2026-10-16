---
title: 汇总计费与会话验收
type: query
tags: [验收, 汇率, 会话]
created: 2026-10-16
updated: 2026-10-16
status: active
---

# 汇总计费与会话验收

## 问题

新增汇率保存接口返回 HTML；OpenCode、Pi 会话详情及趋势缺失；所有 Agent 需要复用主仪表盘并逐来源累加。

## 根因

- 开发前端将 `/api` 代理到 3457，但该端口运行旧的 `dist/server/index.js`，没有新增接口，SPA 页面被当成 JSON 解析。
- OpenCode、Pi 会话索引仅从 Token 事件建立摘要，详情事件列表为空；analytics 路由返回固定空响应。
- 未识别模型套用 Sonnet 价格，前端缓存节省也固定使用 Sonnet 单价。

## 解法

- 构建并重启已确认来自本项目的旧后端，验证 `PUT /api/settings/billing` 和重新读取均返回 6.68。前端检查响应类型并明确显示旧服务问题。
- 从真实消息读取内容和工具事件，重新使用已有 Sessions 展示。补齐所有 Agent 会话来源及详情路由。
- 使用共享模型价格，按用户确认的来源优先级和设置汇率计算。

## 涉及模块

- [所有 Agent 汇总](../entities/all-agents-dashboard.md)
- [模型计费与币种](../entities/model-pricing.md)
- [会话内容与分析](../entities/session-transcripts.md)
- [仪表盘设置入口](../entities/dashboard-settings.md)

## 验证状态

210 项单元测试、类型检查和构建已通过。真实会话解析验收已通过：所有来源共 204 个会话，分页、搜索、模型／状态／项目筛选和汇总详情均已验证。去除 Sessions 重复的 Token、费用总览卡片后，字体改为本地资源后，完整端到端回归 47 项全部通过，包括控制台无错误用例。

![汇率保存成功](assets/billing-settings.png)

## 复发预防

核对实际运行进程与接口行为，不以源码修改推断后端已更新。汇总验收必须使用真实数据校验加总；原有固定夹具回归只验证界面稳定性，不作为真实数据完整性证明。

## 字体资源连接重置

在控制台错误中附加 `msg.location().url` 后，确认两次 `ERR_CONNECTION_RESET` 分别来自 jsDelivr 的 Geist 和 Geist Mono 字体请求。原有控制台检查有效，不应过滤此错误。

从 npm 发布包 `geist@1.3.1` 取得相同版本的两个可变字体，保存到 `src/client/assets/fonts/`，并保留原许可证。CSS 使用相对路径，由 Vite 生成本地静态资源，页面加载不再依赖外部字体服务。未增加 npm 依赖。实际构建已生成两个带内容哈希的本地字体文件；完整端到端回归 47 项全部通过，类型检查通过。
