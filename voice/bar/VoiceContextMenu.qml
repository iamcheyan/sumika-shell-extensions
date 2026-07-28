pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

ContextMenuWindow {
    id: root

    ContextMenuItem {
        nerdIcon: NerdIconMap.cpu
        labelText: "Model Manager (TUI)"
        onClicked: {
            Quickshell.execDetached(["sumika-launch-settings-voice-tui"]);
            root.close();
        }
    }

    ContextMenuSeparator {}

    ContextMenuItem {
        nerdIcon: NerdIconMap.keyboard
        labelText: "Edit Keybindings"
        onClicked: {
            Quickshell.execDetached(["sumika-edit-voice-bindings"]);
            root.close();
        }
    }

}
