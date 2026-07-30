# Sumika Shell Extensions

可扩展模块仓库。每个子目录是一个独立扩展，通过 `module.json` 声明功能，由 Sumika Shell 在启动时发现并加载。

## 扩展列表

| 目录 | 名称 | 描述 |
|------|------|------|
| `active-window` | 当前窗口与桌面状态 | 顶栏左侧活动窗口标题、图标与桌面状态展示 |
| `clipboard` | 剪贴板历史 | 剪贴板内容历史记录与快速粘贴 |
| `file-backup` | 文件备份与分发 | 基于 rsync / Samba 的配置与数据备份机制 |
| `input-method` | 输入法 | Fcitx5 输入法管理（中/日/英切换、Rime 部署） |
| `keyboard-remap` | Keyboard Remapping | 键盘映射配置（keyd 配置、profiles 管理、按键捕获） |
| `screenshot` | 截图工具 | 全屏、区域截图与屏幕录制菜单 |
| `theme-settings` | Theme Settings | 主题选择、视觉效果与配色方案管理 |
| `voice` | Voice Input | 语音输入与语音转文字（支持翻译） |
| `windows-vm` | Windows 虚拟机 | 基于 QEMU / WinApps / LookingGlass 的快捷管理与引导 |

## 扩展结构

每个扩展遵循以下布局：

```
<id>/
  module.json       # v2 manifest（必需）
  qmldir            # QML 模块声明（如提供 QML 组件，必需）
  *.qml             # QML 源文件
  bin/              # 可执行脚本，自动加入 PATH
  popup/            # 顶栏弹出面板组件
  bar/              # 顶栏按钮组件
  settings/         # 设置页面组件
  scripts/          # 辅助脚本
  share/            # 共享数据（polkit 规则等）
```

## 开发指南

### 创建新扩展

1. 在本仓库创建目录 `<id>/`
2. 编写 `module.json`（v2 schema）
3. 如果提供 QML 组件，添加 `qmldir`
4. 可执行脚本放在 `bin/`，启动时自动加入 `PATH`
5. `sumika-modules extensions list` 验证是否被识别

### TUI 浮窗规则

如果扩展包含 TUI 程序，需要在主仓库 `hypr/looknfeel.lua` 的 `sumika_tui_ids` 列表里加上实际 app-id（无下划线形式）。详见主仓库 `AGENTS.md` 的「TUI Terminal Action Pattern」章节。

### 冲突

- Core 模块永远优先。扩展与 core 模块 ID 冲突时扩展静默跳过。
- 启动时扫描按文件名顺序，同名扩展间靠后覆盖前者。

## 安装

扩展由 Sumika Shell 在启动时自动发现 `SUMIKA_SHELL_EXTENSIONS_DIR`（默认 `~/.local/share/sumika-shell/extensions/`）。

```bash
# 克隆到标准路径
git clone git@github.com:iamcheyan/sumika-shell-extensions.git \
  ~/.local/share/sumika-shell/extensions

# 重新启动 shell 即可生效
sumika-restart
```

## 诊断

```bash
sumika-modules extensions list     # 列出已安装扩展
sumika-modules extensions info <id>  # 查看扩展详情
sumika-doctor                       # 运行诊断
```
