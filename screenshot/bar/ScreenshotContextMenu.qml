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
            Quickshell.execDetached(["sumika-screenshot", "fullscreen"]);
            root.close();
        }
    }

    ContextMenuItem {
        nerdIcon: NerdIconMap.desktop
        labelText: "Capture Monitor (3s delay)"
        onClicked: {
            Quickshell.execDetached(["sumika-screenshot", "delay"]);
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
