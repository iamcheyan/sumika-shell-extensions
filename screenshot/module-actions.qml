import QtQuick

import qs.core.runtime
import qs
import Quickshell

/// Screenshot action registrations.
///
/// Registers QML-callback actions (freeze/unfreeze bar overlays) and
/// process actions (capture, edit, OCR). Loaded by ModuleActionHost
/// when the screenshot module is enabled.
Item {
    Component.onCompleted: {
        ActionManager.register("screenshot.freeze", "screenshot", "Freeze screenshot overlays", {
            type: "qml",
            call: function(p) { GlobalStates.screenshotActive = true }
        }, {description: "Hide bar popups before grim capture"})

        ActionManager.register("screenshot.unfreeze", "screenshot", "Unfreeze screenshot overlays", {
            type: "qml",
            call: function(p) { GlobalStates.screenshotActive = false }
        }, {description: "Restore bar popups after grim capture"})

        ActionManager.register("screenshot.capture", "screenshot", "Take region screenshot", {
            type: "process",
            command: ["sumika-screenshot", "screenshot"]
        }, {description: "Capture a selected screen region"})

        ActionManager.register("screenshot.capture-edit", "screenshot", "Take region screenshot and edit", {
            type: "process",
            command: ["sumika-screenshot", "edit"]
        }, {description: "Capture a region and open in editor"})

        ActionManager.register("screenshot.capture-ocr", "screenshot", "Extract text from screenshot", {
            type: "process",
            command: ["sumika-screenshot", "ocr"]
        }, {description: "OCR text from a screen region"})
    }
}
