pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Context menu for the active-window title in the bar.
 *
 * The menu adapts to the compositor:
 *  - labwc:   zwlr_foreign_toplevel_management_v1 handles minimize /
 *             maximize / close (labwc has no IPC and no per-window
 *             float/pin concept surfaced here).
 *  - Hyprland: Hyprland has no usable minimize (windows cannot be
 *             re-raised from the bar), so Minimize/Maximize are replaced
 *             by window ops that actually matter under tiling:
 *             Toggle Floating, Fullscreen, Pop Out (float+pin+top),
 *             Move to Scratchpad. All target the clicked window by
 *             address (bar clicks do not steal toplevel focus).
 *
 * "Force Quit" has no wlr-ftm kill request and labwc has no IPC, so we
 * cannot get the toplevel's PID from the compositor. Instead we map the
 * appId to a process name (last dot segment: org.kde.ark → ark) and signal
 * it directly: SIGTERM first, then SIGKILL if the window survives the
 * grace period. Hyprland keeps its native window-level `killactive`.
 */
ContextMenuWindow {
    id: root

    /// The toplevel the menu was opened for — captured by the bar at click
    /// time so actions hit the window the user clicked on, even if focus
    /// shifts while the menu is open.
    required property var targetToplevel

    readonly property bool isHyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""

    /// "address:0x…" selector for hyprctl dispatch — targets the clicked
    /// window regardless of which window is focused now.
    readonly property string targetAddress: {
        const addr = root.targetToplevel?.HyprlandToplevel?.address ?? "";
        return addr ? "address:0x" + addr : "";
    }

    /// comm-name candidate derived from the appId (org.kde.ark → ark).
    readonly property string targetProcessName: {
        const appId = (root.targetToplevel?.appId ?? "").trim();
        if (!appId)
            return "";
        return appId.split(".").pop().replace(/'/g, "");
    }

    /// hyprctl dispatch with the clicked window's address (Lua syntax).
    function hyprDispatch(lua) {
        const addr = root.targetAddress;
        if (!addr)
            return;
        // hyprctl is Lua-driven in this build; the raw `dispatch` form
        // without address targets the focused window, which may differ
        // from the clicked one.
        Quickshell.execDetached(["hyprctl", "dispatch", lua]);
    }

    function forceQuit() {
        const proc = root.targetProcessName;
        if (!proc)
            return;
        if (root.isHyprland) {
            // Window-level kill for the clicked toplevel. Bar clicks do not
            // steal toplevel focus, so killactive still hits the menu's
            // window; fall back to address-scoped close for reliability.
            Quickshell.execDetached(["hyprctl", "dispatch", "killactive"]);
            return;
        }
        // labwc: SIGTERM the app's process by exact comm name, then
        // SIGKILL via killCheck if the window is still around.
        Quickshell.execDetached(["bash", "-c", `pkill -x '${proc}'`]);
        root.killCheck.restart();
    }

    // SIGTERM did not take (stuck app) — escalate to SIGKILL.
    Timer {
        id: killCheck
        interval: 2000
        onTriggered: {
            const t = root.targetToplevel;
            if (!t)
                return;
            const stillThere = ToplevelManager.toplevels.values.some(x => x === t);
            if (!stillThere)
                return;
            const proc = root.targetProcessName;
            if (!proc)
                return;
            Quickshell.execDetached(["bash", "-c", `pkill -9 -x '${proc}'`]);
        }
    }

    // ── labwc: minimize / maximize (Hyprland hides these) ──────────────
    ContextMenuItem {
        visible: !root.isHyprland
        nerdIcon: NerdIconMap.windowMinimize
        labelText: "Minimize"
        shortcutKey: "M"
        onClicked: {
            console.log("[AWMenu] item=minimize target=", root.targetToplevel?.appId ?? "null");
            if (root.targetToplevel)
                root.targetToplevel.minimized = true;
            root.close();
        }
    }

    ContextMenuItem {
        visible: !root.isHyprland
        nerdIcon: NerdIconMap.windowMaximize
        labelText: "Maximize"
        shortcutKey: "X"
        onClicked: {
            console.log("[AWMenu] item=maximize target=", root.targetToplevel?.appId ?? "null");
            if (root.targetToplevel)
                root.targetToplevel.maximized = !root.targetToplevel.maximized;
            root.close();
        }
    }

    // ── Hyprland: window ops that matter under tiling ──────────────────
    ContextMenuItem {
        visible: root.isHyprland
        nerdIcon: "\uDB81\uDC37" // mdi-flip-to-front U+F0437 — float/tile glyph
        labelText: "Toggle Floating"
        shortcutKey: "F"
        onClicked: {
            console.log("[AWMenu] item=floating target=", root.targetToplevel?.appId ?? "null");
            root.hyprDispatch(`hl.dsp.window.float({ window = "${root.targetAddress}", action = "toggle" })`);
            root.close();
        }
    }

    ContextMenuItem {
        visible: root.isHyprland
        nerdIcon: "\uDB80\uDDB4" // mdi-fullscreen U+F01B4
        labelText: "Fullscreen"
        shortcutKey: "S"
        onClicked: {
            console.log("[AWMenu] item=fullscreen target=", root.targetToplevel?.appId ?? "null");
            root.hyprDispatch(`hl.dsp.window.fullscreen({ window = "${root.targetAddress}", mode = "fullscreen" })`);
            root.close();
        }
    }

    ContextMenuItem {
        visible: root.isHyprland
        nerdIcon: NerdIconMap.pushPin
        labelText: "Pop Out (Float & Pin)"
        shortcutKey: "P"
        onClicked: {
            console.log("[AWMenu] item=popout target=", root.targetToplevel?.appId ?? "null");
            // Mirrors bin/sumika-hyprland-window-pop: float, resize, center,
            // pin, raise to top.
            root.hyprDispatch(`hl.dsp.window.float({ window = "${root.targetAddress}", action = "toggle" })`);
            root.hyprDispatch(`hl.dsp.window.center({ window = "${root.targetAddress}" })`);
            root.hyprDispatch(`hl.dsp.window.pin({ window = "${root.targetAddress}" })`);
            root.hyprDispatch(`hl.dsp.window.alter_zorder({ window = "${root.targetAddress}", mode = "top" })`);
            root.close();
        }
    }

    ContextMenuItem {
        visible: root.isHyprland
        nerdIcon: "\uDB80\uDC8D" // mdi-inbox-arrow-down U+F008D — stash to scratchpad
        labelText: "Move to Scratchpad"
        shortcutKey: "D"
        onClicked: {
            console.log("[AWMenu] item=scratchpad target=", root.targetToplevel?.appId ?? "null");
            root.hyprDispatch(`hl.dsp.window.move({ window = "${root.targetAddress}", workspace = "special:scratchpad", follow = false })`);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.windowClose
        labelText: "Close Window"
        shortcutKey: "C"
        onClicked: {
            console.log("[AWMenu] item=close target=", root.targetToplevel?.appId ?? "null");
            if (root.targetToplevel)
                root.targetToplevel.close();
            root.close();
        }
    }

    ContextMenuSeparator {}

    ContextMenuItem {
        nerdIcon: NerdIconMap.windowKill
        labelText: "Force Quit"
        shortcutKey: "K"
        onClicked: {
            console.log("[AWMenu] item=kill target=", root.targetToplevel?.appId ?? "null");
            root.forceQuit();
            // forceQuit() must run before close(): closing emits menuClosed,
            // which unloads this Loader and destroys the menu object.
            root.close();
        }
    }

    Component.onCompleted: {
        console.log("[AWMenu] opened target=", root.targetToplevel?.appId ?? "null",
            "hyprland=", root.isHyprland);
    }
    Component.onDestruction: {
        console.log("[AWMenu] destroyed");
    }
}
