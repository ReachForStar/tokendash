# TokenDash 能耗优化设计（方案 A+：自适应按需刷新）

- **日期**: 2026-07-03
- **状态**: Draft（待用户审核）
- **范围**: TokenDash 菜单栏 app（Swift）+ Node daemon 的后台轮询能耗优化
- **作者**: brainstorming 会话产出

---

## 1. 背景

用户反馈 TokenDash 后台常驻能耗偏高，活动监视器中 TokenDash / tokendash daemon 进程 CPU 占用明显。TokenDash 是 **Swift 菜单栏 app + 常驻 Node daemon** 双进程结构，真正的耗电不在「进程常驻」本身（Node 事件循环闲置很省），而在于**不管用户是否在看，都在高频干活**。

## 2. 能耗诊断（代码定位）

按严重度，三个热点：

1. **每 5 秒强制重解析日志（最大头）**
   `BadgeUpdater` 有固定 5s tick（`BadgeUpdater.swift:12`，注释自称 "cheap"，但实际不然）。`tick()` 在非刷新周期调用 `samplePulse()`（`:76`），后者对每个 agent 请求 `getDaily(refresh: true)`（`:108`）。`refresh:true` 绕过 daemon 缓存，**重新扫描 `~/.claude/projects/` 等目录解析 JSONL**。等于：用户没看菜单栏，也每 5 秒扫盘+解析一次；会话文件越多 CPU 越高。目的是画「实时 token 速率」脉冲图。

2. **每次刷新全量算 popover 所有图表（不管开没开）**
   `update()`（`:180`）无条件计算 hourly/projects/models/trend 并拉 quota，写多个 `@Observable` 触发 SwiftUI。但菜单栏 badge 只需要「今日总 token 数」一个值，其余仅 popover 打开时才用得到。

3. **每次刷新强打外部 quota API**
   `getQuota(refresh:true)`（`:274`）每周期清掉 daemon 的 60s `QuotaCache`，重新请求 GLM/MiniMax/Kimi/Codex 外部接口。

**非热点**：daemon 常驻本身、`DaemonManager` 30s healthCheck（`isAlive` 不走网络，廉价）。

核心矛盾：**「实时性」被实现成无脑高频轮询，而 95% 时间用户没在看。**

## 3. 竞品调研：exelban/stats

参考 [exelban/stats](https://github.com/exelban/stats)——持续监控网络/系统但功耗约为 TokenDash 的 1%。其省电三根支柱：

| 支柱 | stats 做法 | TokenDash 可借鉴性 |
|---|---|---|
| **① 数据源 inherently 廉价** | 读内核 API（`host_statistics`/`getifaddrs`/SMC），O(1) 微秒级、零磁盘 I/O | **搬不了**——统计 token 用量必须扫日志文件，这是业务本质，也是两者功耗差 ~100× 的根因 |
| **② 同步刷新（Synchronized）** | 所有模块共享一个 timer，一次唤醒做完所有读取+UI 更新 | **已满足**——`BadgeUpdater` 已是单一 Timer |
| **③ 按需启停模块** | 不显示的模块不跑 timer（官方 FAQ：禁用不用的模块降 ~50% CPU） | **可搬**——对应「popover 详情」，目前无差别全算 |

**结论**：stats 无法照搬（数据源是硬约束），但方案 A 的哲学等价于 stats——**让每次轮询尽可能廉价（缓存挡住重解析）+ 不显示的视图不计算（popover 可见性）**。再补一条 stats 启发：**接系统电源通知，睡眠时停轮询**。

## 4. 方案选择

| 方案 | 思路 | 收益 | 代价 | 结论 |
|---|---|---|---|---|
| **A+ 自适应（选定）** | 刷新绑 popover 可见性 + 轮询走缓存 | dormant 期 CPU 归零，体验无损 | 改造中等，风险可控 | ✅ |
| B 事件驱动 | FSEvents 监听日志变化，有新数据才解析 | 理论最省 | daemon 需增量解析、文件监听坑多、风险高 | 未来演进 |
| C 纯降频 | 只调常量 5s→30s | 改动最小 | 治标不治本，体验变迟钝 | ❌ |

**选定方案 A+**：精准命中「CPU 明显 + badge/popover 两者都高频」场景——不看时 CPU 归零，看时全速无损。不堵死未来演进到 B 的路。

## 5. 详细设计

### 5.1 刷新模式状态机

`BadgeUpdater` 引入显式模式：

```swift
enum RefreshMode { case dormant, active, suspended }
private var mode: RefreshMode = .dormant
```

| 模式 | 触发 | 行为 |
|---|---|---|
| `.dormant` | popover 合上（默认） | 60s 周期，只跑 `updateBadge()`（refresh:false 走缓存）。**不**算 hourly/projects/trend、**不**拉 quota、**不**脉冲采样 |
| `.active` | popover 打开（`NSPopover.willShow`） | 立即 `updateFull()`（refresh:true 拿新鲜）；随后每 **10s** `samplePulse()`（refresh:true 算速率 delta）+ 每 **60s** `updateFull()`（refresh:false 走缓存，刷新 hourly/projects/trend/quota 详情视图） |
| `.suspended` | 系统睡眠 / 进入低电量模式 | 停主 timer，仅保留 `DaemonManager` 30s healthCheck（廉价） |

切换由 AppDelegate 驱动：
- `NSPopover.willShow` → `setMode(.active)`
- `NSPopover.willClose` → `setMode(.dormant)`
- `NSWorkspace.willSleepNotification` → `setMode(.suspended)`
- `NSWorkspace.didWakeNotification` → 恢复睡眠前的模式（dormant 或 active）
- `NSProcessInfoPowerStateDidChange` / `isLowPowerModeEnabled` → low-power 时降级 dormant 周期到 120s

### 5.2 轮询瘦身（让每次轮询廉价）

将 `update()` 拆为两个口径：

- **`updateBadge()`（轻）**：仅 `getDaily(refresh:false)` → 聚合今日 total/cost → 更新 `badgeImage`/`tooltipText`/`todaySummary`。不算 hourly/projects/trend、不拉 quota。
- **`updateFull()`（重）**：在 `updateBadge` 基础上 + `getBlocks` + `getProjects` + `getQuota`（**均 refresh:false，走 daemon 缓存**）+ 计算 hourly/projects/models/trend。

Quota 策略：
- badge / dormant 周期：**完全不拉 quota**。
- `updateFull()`：`refresh:false` 命中 daemon 的 60s `QuotaCache`（`src/server/quota/cache.ts`），**不再每周期强刷外部 API**。
- 强刷只在用户手动点「刷新按钮」时：`refreshNow()` 改为调用 `updateFull()` 并带 `refresh:true`（清缓存拿最新）。

脉冲采样：
- 仅 `.active` 模式运行，频率 **10s**（原 5s）。
- `samplePulse()` 保持 `refresh:true`——因为速率 delta 需要相对新鲜的今日累计值，走 5min 缓存会让连续两次采样拿到同值导致速率恒为 0。
- 权衡：active 期每 10s 重解析一次（用户在看，可接受，且比原 5s 省一半）；dormant 期完全不采样（CPU 归零的关键）。

**active 期详情视图刷新**：脉冲只调 `getDaily`，不刷新 hourly/projects/trend/quota。为让这些详情视图在 popover 打开期间也保持新鲜，active 模式额外每 60s 跑一次 `updateFull(refresh:false)`——走 daemon 缓存，**不触发重解析**（5min 内命中缓存），Swift 端只是周期性轻量计算 + UI 更新，daemon CPU 几乎不增。

### 5.3 daemon 端配合（缓存挡住重解析）

Swift 端默认改 `refresh:false` 后，daemon 现有缓存即可生效：
- usage 缓存：`src/server/cache.ts`，`DEFAULT_TTL = 5min`（内存 + 磁盘 stale-while-revalidate）。
- quota 缓存：`src/server/quota/cache.ts`，`ttlMs = 60s`。

**效果**：「扫盘解析 JSONL」的频率从**每 5s → 每 5min**（仅当 dormant 周期命中缓存过期那次 daemon 才真正解析）。这是 dormant 期 CPU 归零的核心来源。

**daemon 基本无需改动**（缓存机制已存在），改动主要在 Swift 端调整 `refresh` 参数与 `tick` 分支。

### 5.4 可靠性 / 错误处理

- daemon 崩溃 / 被回收 → `DaemonManager` 30s healthCheck 自愈 + `BadgeUpdater.updatePort` 热切换端口（已有机制，见 cerebrum 2026-06-19 条目）。模式状态在端口热切换时保持。
- popover 打开瞬间数据 stale → 走现有 stale-while-revalidate，先显示旧数据，后台 revalidate 后刷新。
- 模式切换幂等：重复 `setMode(.active)` 不会叠加多个脉冲 timer。

### 5.5 测试策略

- **单元（Swift）**：
  - `BadgeUpdater` 模式切换：mock popover 可见性，断言 dormant 不触发 blocks/projects/quota 请求（用 mock APIClient 计数）。
  - dormant 周期 60s、active 脉冲 10s 的计时正确性。
- **单元（daemon，已有）**：扩展 `src/__tests__/server/cache.test.ts`，验证 `refresh:false` 命中 5min 缓存、`refresh:true` 绕过。
- **手动验收**：活动监视器观察 popover 合上 5min 后 TokenDash + daemon 的 CPU 是否降到接近 0。

## 6. 关键决策记录

| 决策 | 选择 | 理由 |
|---|---|---|
| dormant badge 周期 | 60s | badge 瞄一眼无需更实时；可后续做成用户可调 |
| 脉冲采样频率（active） | 10s | 用户拍板：图够细腻，CPU 较 5s 减半 |
| 脉冲是否走缓存 | 否（refresh:true） | 速率 delta 需新鲜值，走缓存会让速率恒为 0 |
| quota 拉取 | 周期走 60s 缓存，仅手动刷新强刷 | 消除每周期外部 API 调用 |
| 系统电源感知 | 接入 | stats 启发；睡眠/低电量停轮询 |

## 7. 范围

**In scope**：
- `BadgeUpdater`：模式状态机 + `update()` 拆分 + refresh 参数调整 + 脉冲仅在 active。
- AppDelegate：popover 开闭 + 系统电源通知 hook，驱动 `setMode`。
- quota 走缓存、手动刷新强刷。
- 手动验收 + 单测扩展。

**Out of scope（未来演进）**：
- 方案 B：FSEvents 事件驱动 + daemon 增量解析。
- 把 daemon 的 TS 解析逻辑迁移到 Swift 原生（消除 Node 进程）。
- 浏览器 dashboard 版的能耗。

## 8. 验收标准

1. popover 合上 ≥5min 后，活动监视器中 TokenDash + tokendash daemon 的平均 CPU 接近 0（< 0.5%）。
2. dormant 期 badge 仍每 60s 更新今日 token 数（缓存值）。
3. popover 打开 → 1s 内全量数据可见；实时速率图每 10s 刷新一次。
4. 系统睡眠 → 主轮询停止；唤醒 → 自动恢复。
5. 无功能回归：badge 显示、quota 卡片、dashboard 按钮、daemon 崩溃自愈均正常。

## 9. 风险

- **NSPopover 通知可靠性**：项目已用 NSStatusItem + NSPopover（非 MenuBarExtra，见 cerebrum 2026-06-11）。需确认现有 AppDelegate 能稳定接收 `willShow/willClose`；若不可靠，回退用 popover delegate (`popoverDidShow`/`popoverDidClose`)。
- **active 期仍每 10s 解析**：会话文件极大时 active CPU 仍不低，但仅限用户主动查看期间，可接受；若需进一步优化，触发方案 B。
