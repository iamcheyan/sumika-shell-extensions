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
            Quickshell.execDetached(["omd-screenshot", "screenshot"]);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.edit
        labelText: "Capture && Edit"
        onClicked: {
            Quickshell.execDetached(["omd-screenshot", "edit"]);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.camera
        labelText: "Capture Fullscreen"
        onClicked: {
            Quickshell.execDetached(["bash", "-c",
                "grim -o $(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name') - | wl-copy && notify-send -i camera-photo Screenshot \"Full screen copied to clipboard\""
            ]);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.desktop
        labelText: "Capture Monitor (3s delay)"
        onClicked: {
            Quickshell.execDetached(["bash", "-c",
                "monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'); notify-send -i camera-photo Screenshot \"Capturing current monitor in 3 seconds\"; sleep 3; grim -o \"$monitor\" - | wl-copy && notify-send -i camera-photo Screenshot \"Current monitor copied to clipboard\""
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
            Quickshell.execDetached(["omd-screenshot", "record"]);
            root.close();
        }
    }

    ContextMenuSeparator {}

    ContextMenuItem {
        nerdIcon: NerdIconMap.textDocument
        labelText: "OCR Recognize"
        onClicked: {
            Quickshell.execDetached(["omd-screenshot", "ocr"]);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.settings
        labelText: "OCR Settings"
        onClicked: {
            Quickshell.execDetached(["omd-launch-ocr-tui"]);
            root.close();
        }
    }

    ContextMenuSeparator {}

    ContextMenuItem {
        nerdIcon: NerdIconMap.visibilityOff
        labelText: "Hide"
        onClicked: {
            var hidden = Config.options.bar.hiddenIcons;
            var alreadyHidden = false;
            for (var i = 0; i < hidden.length; i++) {
                if (hidden[i] === "screenshot") {
                    alreadyHidden = true;
                    break;
                }
            }
            if (!alreadyHidden) {
                var newHidden = [];
                for (var i = 0; i < hidden.length; i++)
                    newHidden.push(hidden[i]);
                newHidden.push("screenshot");
                Config.setNestedValue("bar.hiddenIcons", newHidden);
            }
            root.close();
        }
    }
}
