pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

ContextMenuWindow {
    id: root

    ContextMenuItem {
        nerdIcon: NerdIconMap.screenshot
        labelText: "Capture Area"
        onClicked: {
            // Do not close here: freeze runs after slurp's mask is mapped so
            // the menu disappears under the darken overlay (no bright flash).
            Quickshell.execDetached(["sumika-screenshot", "screenshot"]);
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.edit
        labelText: "Capture && Edit"
        onClicked: {
            // Freeze is deferred until the region selector overlay is visible
            // (frozen snapshot already includes this menu).
            Quickshell.execDetached(["sumika-screenshot", "edit"]);
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.camera
        labelText: "Capture Fullscreen"
        onClicked: {
            Quickshell.execDetached(["bash", "-c",
                "f=$(mktemp /tmp/sumika-screenshot-full.XXXXXX.png); " +
                "_prev_invis=$(hyprctl getoption cursor:invisible -j 2>/dev/null | jq -r '.bool // false' 2>/dev/null || echo false); " +
                "hyprctl eval \"hl.config({ cursor = { invisible = true } })\" >/dev/null 2>&1 || true; " +
                "sleep 0.03; " +
                "grim -o $(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name') \"$f\"; " +
                "if [ \"$_prev_invis\" = true ]; then hyprctl eval \"hl.config({ cursor = { invisible = true } })\" >/dev/null 2>&1 || true; " +
                "else hyprctl eval \"hl.config({ cursor = { invisible = false } })\" >/dev/null 2>&1 || true; fi; " +
                "cliphist store < \"$f\" 2>/dev/null || true; " +
                "wl-copy --type image/png < \"$f\"; " +
                "rm -f \"$f\"; " +
                "notify-send -i camera-photo Screenshot \"Full screen copied to clipboard\""
            ]);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.desktop
        labelText: "Capture Monitor (3s delay)"
        onClicked: {
            Quickshell.execDetached(["bash", "-c",
                "f=$(mktemp /tmp/sumika-screenshot-delay.XXXXXX.png); " +
                "monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'); " +
                "notify-send -i camera-photo Screenshot \"Capturing current monitor in 3 seconds\"; " +
                "sleep 3; " +
                "_prev_invis=$(hyprctl getoption cursor:invisible -j 2>/dev/null | jq -r '.bool // false' 2>/dev/null || echo false); " +
                "hyprctl eval \"hl.config({ cursor = { invisible = true } })\" >/dev/null 2>&1 || true; " +
                "sleep 0.03; " +
                "grim -o \"$monitor\" \"$f\"; " +
                "if [ \"$_prev_invis\" = true ]; then hyprctl eval \"hl.config({ cursor = { invisible = true } })\" >/dev/null 2>&1 || true; " +
                "else hyprctl eval \"hl.config({ cursor = { invisible = false } })\" >/dev/null 2>&1 || true; fi; " +
                "cliphist store < \"$f\" 2>/dev/null || true; " +
                "wl-copy --type image/png < \"$f\"; " +
                "rm -f \"$f\"; " +
                "notify-send -i camera-photo Screenshot \"Current monitor copied to clipboard\""
            ]);
            root.close();
        }
    }

    ContextMenuSeparator {}

    ContextMenuItem {
        nerdIcon: NerdIconMap.eyeDropper
        labelText: "Color Picker"
        onClicked: {
            Quickshell.execDetached(["hyprpicker", "-a"]);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.video
        labelText: "Record Screen"
        onClicked: {
            // QML selector: mask → region → countdown → highlight + Stop bar.
            Quickshell.execDetached(["sumika-screenshot", "record"]);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.video
        labelText: "Record Screen (with audio)"
        onClicked: {
            Quickshell.execDetached(["sumika-screenshot", "recordWithSound"]);
            root.close();
        }
    }

    ContextMenuSeparator {}

    ContextMenuItem {
        nerdIcon: NerdIconMap.textDocument
        labelText: "OCR Recognize"
        onClicked: {
            Quickshell.execDetached(["sumika-screenshot", "ocr"]);
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.settings
        labelText: "OCR Settings"
        onClicked: {
            Quickshell.execDetached(["sumika-launch-ocr-tui"]);
            root.close();
        }
    }

}
