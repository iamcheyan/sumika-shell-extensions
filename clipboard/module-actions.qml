import QtQuick

import qs.core.runtime
import Quickshell

/// Clipboard action registrations.
///
/// Registers process actions for clipboard history management.
/// Loaded by ModuleActionHost when the clipboard module is enabled.
Item {
    Component.onCompleted: {
        var clipDir = ModuleLoader.modulePath("clipboard")
        if (!clipDir) return

        ActionManager.register("clipboard.store-toggle", "clipboard", "Toggle clipboard store", {
            type: "process",
            command: [clipDir + "/bin/omd-clipboard-store", "toggle"]
        }, {description: "Start or stop the clipboard history daemon"})

        ActionManager.register("clipboard.toggle", "clipboard", "Toggle clipboard", {
            type: "process",
            command: [clipDir + "/bin/omd-clipboard", "toggle"]
        }, {description: "Open or close the clipboard history"})

        ActionManager.register("clipboard.toggleBar", "clipboard", "Toggle clipboard at bar", {
            type: "shell",
            command: clipDir + "/bin/omd-clipboard toggle-at-bar"
        }, {description: "Open or close the clipboard anchored to the top bar"})

        ActionManager.register("clipboard.open", "clipboard", "Open clipboard", {
            type: "process",
            command: [clipDir + "/bin/omd-clipboard", "open"]
        }, {description: "Open the clipboard history"})

        ActionManager.register("clipboard.close", "clipboard", "Close clipboard", {
            type: "process",
            command: [clipDir + "/bin/omd-clipboard", "close"]
        }, {description: "Close the clipboard history"})

        ActionManager.register("clipboard.paste", "clipboard", "Paste clipboard selection", {
            type: "process",
            command: [clipDir + "/bin/omd-clipboard", "paste"]
        }, {description: "Paste the currently selected clipboard entry"})
    }
}
