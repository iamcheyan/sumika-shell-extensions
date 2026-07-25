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
            Quickshell.execDetached(["omd-launch-settings-voice-tui"]);
            root.close();
        }
    }

    ContextMenuSeparator {}

    ContextMenuItem {
        nerdIcon: NerdIconMap.keyboard
        labelText: "Edit Keybindings"
        onClicked: {
            Quickshell.execDetached(["omd-edit-voice-bindings"]);
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
                if (hidden[i] === "voice") {
                    alreadyHidden = true;
                    break;
                }
            }
            if (!alreadyHidden) {
                var newHidden = [];
                for (var i = 0; i < hidden.length; i++)
                    newHidden.push(hidden[i]);
                newHidden.push("voice");
                Config.setNestedValue("bar.hiddenIcons", newHidden);
            }
            root.close();
        }
    }
}
