import QtQuick

import qs.modules.keyboardremap as KeyboardRemapMod
import qs.core.runtime

/// Keyboard remap action registrations.
///
/// Registers QML-callback actions for the keyboard-remap module.
/// Loaded by ModuleActionHost when the keyboard-remap module is enabled.
Item {
    Component.onCompleted: {
        var kr = KeyboardRemapMod.KeyboardRemap

        ActionManager.register("keyboard-remap.toggle", "keyboardremap",
            "Toggle keyboard remap settings", {
            type: "qml",
            call: function(p) {
                kr.openSettings()
            }
        }, {description: "Open or focus the keyboard remap settings page"})

        ActionManager.register("keyboard-remap.refresh", "keyboardremap",
            "Refresh keyboard devices and profiles", {
            type: "qml",
            call: function(p) {
                kr.refreshDevices()
                kr.loadProfiles()
                kr.checkKeyd()
                kr.checkPendingChanges()
                kr.refreshFunctionRow()
            }
        }, {description: "Re-scan keyboards and reload saved profiles"})

        ActionManager.register("keyboard-remap.apply", "keyboardremap",
            "Apply pending keyboard remap changes", {
            type: "qml",
            call: function(p) {
                kr.apply()
            }
        }, {description: "Generate keyd config and install it"})
    }
}
