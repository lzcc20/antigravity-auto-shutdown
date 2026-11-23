<div align="center">
  <img src="assets/logo.svg" alt="Auto Shutdown Logo" width="76" height="76" />
  <h1>Auto Shutdown · 反重力原生风格自动关机插件</h1>
  <p>
    <strong>无缝融入 Antigravity 原生界面的任务守卫与自动关机插件。</strong><br/>
    通过官方生命周期钩子实时追踪所有并行对话与后台任务，确认全部彻底空闲后倒计时执行关机 / 休眠 / 睡眠；基于官方 MCP Apps 原生嵌入 Antigravity 侧边栏、右侧辅助面板与对话流，自动继承宿主深浅主题与字体，看不出是外部插件。
  </p>

  <p>
    <a href="README.md">English</a> ·
    <a href="#原生界面预览">界面预览</a> ·
    <a href="#安装方式">安装方式</a> ·
    <a href="#工作原理与防误关设计">防误关设计</a> ·
    <a href="#对话与命令行控制">对话与命令行</a> ·
    <a href="CHANGELOG.md">更新日志</a>
  </p>

  <p>
    <img src="https://img.shields.io/badge/Antigravity-MCP_App_%2B_Hooks-181A1F?style=flat-square" alt="Antigravity MCP App + Hooks" />
    <img src="https://img.shields.io/badge/运行依赖-零依赖-2F855A?style=flat-square" alt="零依赖" />
    <img src="https://img.shields.io/badge/License-MIT-555?style=flat-square" alt="MIT License" />
    <img src="https://img.shields.io/badge/全平台支持-Windows_%7C_macOS_%7C_Linux-3A3F4B?style=flat-square" alt="全平台支持" />
  </p>
</div>

---

## 原生界面预览

完全遵循 Antigravity 原生视觉体系：直接读取宿主实时 CSS 变量（`--color-background-*`、`--color-text-*`、`--color-border-*`、`--font-sans`）并设置 `prefersBorder: false`，无外挂悬浮窗违和感，自动跟随 Antigravity 深浅色切换，支持一键 `中 / EN`。

<div align="center">
  <p><strong>左侧导航栏完整视图（左侧边栏 → Plugins → Auto Shutdown）</strong></p>
  <img src="assets/preview-fullpage-dark.png" alt="全屏原生设置视图" width="720" />
</div>

<br/>

<div align="center">
  <table>
    <tr>
      <td align="center"><strong>右侧辅助面板 · 深色（倒计时状态）</strong></td>
      <td align="center"><strong>右侧辅助面板 · 浅色（多任务监测中）</strong></td>
    </tr>
    <tr>
      <td align="center"><img src="assets/preview-sidepanel-dark.png" alt="右侧面板深色" width="340" /></td>
      <td align="center"><img src="assets/preview-sidepanel-light.png" alt="右侧面板浅色" width="340" /></td>
    </tr>
  </table>
</div>

<br/>

<div align="center">
  <p><strong>对话内嵌状态卡（直接渲染在聊天消息流中）</strong></p>
  <img src="assets/preview-inline-dark.png" alt="对话内嵌卡片" width="540" />
</div>

---

## 在 Antigravity 里如何打开（3 种原生入口）

安装完成后，无需启动任何额外窗口，直接在 Antigravity 里使用：

1. **右侧辅助面板（Side Panel）**：点右侧面板顶部的 **`+`**（或 **Overview → Plugins → Auto Shutdown**），像内置标签页一样停靠在对话右侧，边跑任务边看状态；
2. **左侧主导航栏（Full Page）**：在左侧栏 **Plugins → Auto Shutdown** 打开设置风格完整面板；
3. **对话内嵌卡片（Inline）**：在聊天框输入 `/auto-shutdown` 或直接说“打开自动关机面板 / 开启任务完成后自动关机”；
4. *(可选)* **Windows 独立右下角桌边胶囊**：如果你把 Antigravity 最小化时也想在系统任务栏上方看状态，可随时运行 `node scripts/ctl.mjs ui` 手动唤起。

---

## 核心特性

- **精准识别多会话 & 后台任务**：基于 Antigravity 官方 `hooks.json`（`SessionStart`、`PreInvocation`、`PostToolUse`、`PostInvocation`、`Stop`），完全不干涉工具权限审批（不拦截 `PreToolUse`）；严格读取 `Stop` 的 `fullyIdle` 字段，只要仍有后台命令、定时器或子代理在跑就不会提前关机。
- **并行任务并发安全**：采用跨进程文件锁 + 原子 JSON 写入，哪怕同时运行多个并行会话或 Swarm 代理，也只有当**所有**活跃任务都清空时才会进入倒计时。
- **多重防误关机保护**
  - **默认单次布防（One-shot）**：触发关机*之前*自动解除布防，确保下次开机正常对话不会意外关机。
  - **缓冲倒计时 + 唤醒自动撤回**：默认 2 分钟缓冲（支持 `30s / 60s / 2m / 5m`），期间一旦有任何新对话、工具调用或子代理唤醒，立刻自动取消倒计时。
  - **手动中断 / 报错保护**：支持分别开关「手动中断不触发（`USER_CANCELED`）」与「错误终止不触发（`ERROR`）」。
  - **僵尸会话自动清理**：结合活跃时间与 `transcript.jsonl` 修改时间自动淘汰意外关闭的残余会话。
  - **安全演练模式**：底部自带 `安全演练 (15s)` 按钮，一键体验完整倒计时与取消流程，绝不真正关机。
- **零运行依赖、全平台一致**：纯 Node.js ESM MCP 服务端 + 预打包单文件 MCP App 界面（`ui/app.html`），无需 `npm install`，Windows / macOS / Linux 开箱即用。

---

## 安装方式

### 方式一：通过 Antigravity CLI 安装（推荐）

```bash
git clone https://github.com/lzcc20/antigravity-auto-shutdown.git
agy plugin install ./antigravity-auto-shutdown
```

### 方式二：一键安装脚本

**Windows**
```cmd
git clone https://github.com/lzcc20/antigravity-auto-shutdown.git
cd antigravity-auto-shutdown
install.bat
```

**macOS / Linux**
```bash
git clone https://github.com/lzcc20/antigravity-auto-shutdown.git
cd antigravity-auto-shutdown
sh install.sh
```

> 个人偏好与运行状态保存在 `~/.gemini/config/auto-shutdown/`，更新或重装插件不会丢失配置。

### 卸载

运行 `uninstall.bat`（Windows）或 `sh uninstall.sh`（macOS / Linux），或在 Antigravity 的 **Customizations** 插件页直接卸载。

---

## 工作原理与防误关设计

1. 任意对话开始推理（`PreInvocation`）或工具完成（`PostToolUse`）时，登记该 `conversationId` 为活跃状态；如果当时正处于倒计时，**立即取消关机**。
2. 对话结束触发 `Stop` 时：
   - 若 `fullyIdle === false`：说明仍有后台任务在运行，标记为“后台任务”，不关机；
   - 若 `fullyIdle === true`：注销该会话，并检查全局是否还有其他并行会话仍在运行。
3. 当活跃会话数归零且处于布防状态时，启动独立后台倒计时进程（`countdown-worker.mjs`），每 500ms 复核状态文件，倒计时归零前自动解除单次布防，随后执行 `关机` / `休眠` / `睡眠`。

> **夜间挂机建议**：搭配 Antigravity 内置的 `/goal` 命令运行长任务，并在开跑前点击「开启布防」。注意：在启用插件*之前*就已经在跑的对话，要等到它下一次触发钩子时才会被登记。

---

## 对话与命令行控制

在 Antigravity 对话框中可直接使用 `/auto-shutdown`，或在终端执行：

| 命令 | 说明 |
| --- | --- |
| `node scripts/ctl.mjs status` | 查看当前守卫状态、活跃任务与倒计时 |
| `node scripts/ctl.mjs arm --mode once --action shutdown --grace 120` | 开启单次布防（2 分钟倒计时后关机） |
| `node scripts/ctl.mjs arm --mode continuous --action hibernate --grace 60` | 开启持续守候（60 秒后休眠） |
| `node scripts/ctl.mjs disarm` | 关闭布防并取消当前倒计时 |
| `node scripts/ctl.mjs cancel` | 仅取消当前倒计时 |
| `node scripts/ctl.mjs preview --seconds 15` | 启动 15 秒安全演练倒计时（不关机） |
| `node scripts/ctl.mjs clear-stale` | 手动清理残留的活跃任务记录 |
| `node scripts/ctl.mjs ui` | 可选：唤起 Windows 独立桌面右下角胶囊 |

---

## 本地测试与校验

```bash
# 运行核心引擎与 MCP App 服务端测试
node --test tests/engine.test.mjs tests/mcp.test.mjs

# 使用 Antigravity 官方校验器严格检查插件
agy plugin validate --strict .
```

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。第三方开源声明见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
