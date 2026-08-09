pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Context menu for the active-window title in the bar.
 *
 * Minimize / maximize / close go through the compositor-agnostic
 * zwlr_foreign_toplevel_management_v1 API (works on labwc and Hyprland).
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

    /// comm-name candidate derived from the appId (org.kde.ark → ark).
    readonly property string targetProcessName: {
        const appId = (root.targetToplevel?.appId ?? "").trim();
        if (!appId)
            return "";
        return appId.split(".").pop().replace(/'/g, "");
    }

    function forceQuit() {
        const proc = root.targetProcessName;
        if (!proc)
            return;
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
            // Window-level kill for the focused toplevel. Bar clicks do not
            // steal toplevel focus, so this still hits the menu's window.
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

    ContextMenuItem {
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
        console.log("[AWMenu] opened target=", root.targetToplevel?.appId ?? "null");
    }
    Component.onDestruction: {
        console.log("[AWMenu] destroyed");
    }
}
