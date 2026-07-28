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
            Quickshell.execDetached(["sumika-screenshot", "screenshot"]);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.edit
        labelText: "Capture && Edit"
        onClicked: {
            Quickshell.execDetached(["sumika-screenshot", "edit"]);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.camera
        labelText: "Capture Fullscreen"
        onClicked: {
            Quickshell.execDetached(["bash", "-c",
                "f=$(mktemp /tmp/sumika-screenshot-full.XXXXXX.png); " +
                "grim -o $(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name') \"$f\"; " +
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
                "grim -o \"$monitor\" \"$f\"; " +
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
            Quickshell.execDetached(["sumika-screenshot", "record"]);
            root.close();
        }
    }

    ContextMenuSeparator {}

    ContextMenuItem {
        nerdIcon: NerdIconMap.textDocument
        labelText: "OCR Recognize"
        onClicked: {
            Quickshell.execDetached(["sumika-screenshot", "ocr"]);
            root.close();
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
