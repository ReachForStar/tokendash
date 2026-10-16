# Wiki 操作日志

> 只追加、不修改历史。可用 `grep "^## \[" docs/wiki/log.md | tail -5` 看最近记录。
> 前缀格式：`## [YYYY-MM-DD] <init|feat|fix|query|lint|chore> | <简述>`

## [2026-09-17] init | wiki-memory hook 自动创建知识库骨架

## [2026-09-17] feat | 沉淀 pi 本地模型 token 估算

- 决策：为不返回 usage 的本地模型（amax 代理 qwen-3.8-27B）按内容估算 token，新增 estimatedTokens 区分真实/估算（decisions/estimate-tokens-for-no-usage-models.md）
- 实体：pi 解析器模块页（entities/pi-parser.md）
- 排查：Windows 终端 Ctrl+C 退出乱码根因 = 控制台代码页 936/GBK（queries/windows-ctrlc-utf8-gbk-garbled.md）

## [2026-10-16] fix | 更换仪表盘设置图标

- [仪表盘设置入口](entities/dashboard-settings.md)：改用齿轮，保留原有点击行为和无障碍名称；203 项单元测试及浏览器点击验证通过。
