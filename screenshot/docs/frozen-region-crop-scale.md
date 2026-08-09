# 冻结截图整屏回归：根因与修复

## 背景

`screenshot` 扩展的「冻结截图」（Capture & Edit）路径分两步：

1. 先 `grim -o` 截取整屏**物理像素**快照（如 eDP-1 → 3024x1964）；
2. 用户在 QML 选择器里框选区域，代码用 `monitorScale` 把 QML 坐标换算成快照像素，再 `magick -crop` 裁出所选区域。

回归症状：无论框选多小的区域，输出都是**整张桌面**。普通截图（快速区域截图）不受影响。

## 根因

`RegionSelection.qml` 里：

```qml
readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
readonly property real monitorScale: hyprlandMonitor?.scale ?? 1
```

在 **labwc**（非 Hyprland compositor）下：

1. Hyprland IPC 未连接，`Hyprland.monitorFor()` 走 `findMonitorByName(name, createIfMissing=true)`，**创建一个占位 `HyprlandMonitor`**（qslog 可见 `Monitor "eDP-1" requested before creation, performing early init`）；
2. 占位 monitor 的 `scale` 是 `Q_OBJECT_BINDABLE_PROPERTY`，默认构造值为 **0.0**（`updateInitial()` 不设置 scale，hyprctl 事件在 labwc 下永远不会到来）；
3. JS 的 `??` 只在 `null`/`undefined` 时兜底，`0.0 ?? 1` 结果是 **0**；
4. `scaledSnapshotCoord = 坐标 × 0 = 0` → `magick -crop 0x0+0+0 +repage` → ImageMagick 对越界/零尺寸裁剪返回**整图**。

### 证据链

- **运行时产物**：多次冻结截图的 temp 文件全部为整图 3024x1964；
- **Quickshell 源码**：`src/wayland/hyprland/ipc/connection.cpp` 的 `findMonitorByName`（early init 分支）、`monitor.hpp` 的 `Q_OBJECT_BINDABLE_PROPERTY(HyprlandMonitor, qreal, bScale, ...)`（默认 0）；
- **qslog**：early-init 日志确认占位 monitor 被创建；
- **IM7 实测**：`magick in.png -crop 0x0+0+0 +repage out.png` 返回整图。

### 为什么普通截图正常

普通路径用 `slurp` 输出逻辑坐标，`grim -g` **内部**按输出 scale 换算成物理像素。换算发生在 grim 内部，不依赖 QML 的 `monitorScale`，所以永远正确。冻结路径的换算在 QML 里，被 labwc 下的 `scale=0` 击穿。

## 修复

`monitorScale` 不再信任 Hyprland IPC，改为从快照**实际像素尺寸**推导：

```qml
readonly property real monitorScale: {
    const srcW = frozenSnapshot.sourceSize.width;
    if (srcW > 0 && root.screen && root.screen.width > 0) {
        return srcW / root.screen.width;
    }
    return (root.hyprlandMonitor && root.hyprlandMonitor.scale > 0)
        ? root.hyprlandMonitor.scale
        : 1;
}
```

`frozenSnapshot` 是显示冻结画面的 `Image`，其 `sourceSize` 即 grim 输出的物理像素尺寸；`screen.width` 是 QML 坐标。两者之比就是「快照像素 / QML 坐标」的换算因子：

- QML 坐标为逻辑坐标（如 1512）→ 比值 = 显示 scale（2.0）；
- QML 坐标为物理坐标（如 3024）→ 比值 = 1.0。

两种情况下裁剪几何都正确，与 compositor 无关，不再需要 Hyprland IPC。`sourceSize` 未就绪时按顺序回退：`hyprlandMonitor.scale`（须 >0）→ 1。

## 验证

- **模拟**（对真实快照跑 magick）：旧代码 `-crop 0x0+0+0` → 输出 3024x1964 整图（复现 bug）；新代码对区域 600x400+500+300 → scale 2.0 时正确裁出 1200x800；
- **用户实测**（labwc，eDP-1 scale 2.0）：冻结截图框选小区域 → 输出为该区域，不再是整屏。

## 附注（同次提交的配套改动）

- **还原 action-bar 5 个按钮**：从 `getCommand(...)`（对完整快照重裁）改回 `getTempFileCommand(tempScreenshotPath)`（作用于已裁好的 temp）。原因是 `getCommand` 的脚本里 `trap 'rm -f "$tmpFile" "$screenshotFile"' EXIT` 会**删除 pre-cap 共享快照**（`preCapSnapshot=true` 时快照由 shell 脚本创建、多 monitor 实例共用，按设计不应删除）；
- **保留 onReleased 时的 region materialize + `dragging = false`**：regionX/Y/Width/Height 是 `draggingX/Y` 的绑定，若保持绑定，选择完成后指针移向 action bar 会改变裁剪几何；release 时固化为字面值可防止该问题。

代码位置：`apps/sumika-screenshot/regionSelector/RegionSelection.qml` 的 `monitorScale` 属性及 action bar。
