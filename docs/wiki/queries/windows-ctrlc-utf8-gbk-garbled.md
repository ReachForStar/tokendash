---
title: Windows 终端 Ctrl+C 退出乱码（代码页 936/GBK）
type: query
tags: [windows, 代码页, 乱码, powershell, npm]
created: 2026-09-17
updated: 2026-09-17
status: active
---

# Windows 终端 Ctrl+C 退出乱码（代码页 936/GBK）

## 问题

在 Windows 终端跑 `npm run dev`（`concurrently` 起 `tsx watch` + `vite` 两个子进程，
标记 `[0]`/`[1]`）后按 Ctrl+C 退出，控制台出现乱码：

```
0] 禁止操作...(Y/N)?
[1] 禁止操作...(Y/N)?
PS D:\file\tokendash>
[0] npm run dev:server exited with code 1
[1] npm run dev:client exited with code 1
```

注意首行 `[0]` 变成了 `0]`——`[` 被「吃掉」了。这是字节级乱码的典型特征。

## 根因（有证据）

**控制台代码页是 936（GBK/GB2312），而被中断的进程用 UTF-8 输出了中文 `(Y/N)?`
确认提示，UTF-8 字节被 GBK 控制台误解码 → 乱码。**

证据（本机实测）：
- `chcp` → **936**（活动代码页 = GBK）。
- `pwsh` 里 `[Console]::OutputEncoding.WebName` / `InputEncoding` → **gb2312**
  （pwsh 继承控制台代码页，尽管 .NET Core 内部默认是 UTF-8）。
- 默认终端是 **PowerShell 7（pwsh 7.6.6）**（Windows Terminal `defaultProfile`
  GUID `{574e775e-...}` 对应 “PowerShell”），另装有 **Windows PowerShell 5.1**
  （GUID `{61c54bbd-...}`）。两者对原生子进程输出都走系统控制台代码页 936。
- `[` 被吃掉：GBK 是双字节，前导字节 0x81–0xFE 会把紧随的 ASCII 低字节（如 `[`=0x5B）
  当作后导字节消费掉，于是 `[0]` 显示成 `0]`。这只能发生在「非 GBK 字节流被按 GBK
  解码」时，坐实了代码页不匹配。

被中断进程（npm→`cmd.exe /d /s /c`→node）在 Ctrl+C 时打印的本地化中文确认提示
（形如“终止/禁止…(Y/N)?”）是乱码来源。它不在项目源码、`node_modules`、`.pi`、
esbuild、cmd.exe/conhost 资源里（均已检索），属于系统/运行时本地化串；**具体来源
不影响结论与修复**——只要控制台按 UTF-8 解码即可正常显示。

## 解法（任选，推荐 1+2）

1. **会话级快速修复**：在当前终端执行 `chcp 65001`，把代码页切到 UTF-8。
2. **持久化（PowerShell profile）**：在 `~/.config/powershell/Microsoft.PowerShell_profile.ps1`
   （pwsh）或 `Documents\PowerShell\profile.ps1`（5.1）加：
   ```powershell
   chcp 65001 | Out-Null
   [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
   $OutputEncoding = [System.Text.Encoding]::UTF8
   ```
3. **Windows Terminal**：给对应 profile 设 `"initialCodePage": 65001`（新版支持）。
4. **系统级（最彻底但影响面大）**：区域设置里开启“使用 Unicode UTF-8 提供全球语言
   支持”（Beta）。会让系统默认代码页变 UTF-8，但可能影响旧程序，谨慎。

> 关键点：进程侧（node/vite/tsx）默认输出 UTF-8，所以正确方向是**把控制台改成
> UTF-8（65001）**，而不是让进程改输出 GBK。

## 涉及模块

- 不涉及 tokendash 代码；纯 Windows 终端/代码页环境问题。
- 与 `npm run dev`（`concurrently`）的 Ctrl+C 行为相关，但乱码本身由代码页造成。

## 复发预防

- 新环境装好 pwsh 后，profile 里固定 `chcp 65001` + UTF-8 编码。
- 见到“中文变乱码 + 个别 ASCII 符号丢失”先查 `chcp` 与 `[Console]::OutputEncoding`。
