import QtQuick

import qs.modules.voice
import qs.core.runtime

/// Voice input action registrations.
///
/// Registers QML-callback actions for toggling/cancelling voice input
/// via the VoiceInput service. Loaded by ModuleActionHost when the
/// voice module is enabled.
Item {
    Component.onCompleted: {
        ActionManager.register("voice.toggle", "voice", "Toggle voice input", {
            type: "qml",
            call: function(p) { VoiceInput.toggle() }
        }, {description: "Start or stop voice input recording"})

        ActionManager.register("voice.cancel", "voice", "Cancel voice input", {
            type: "qml",
            call: function(p) { VoiceInput.cancel() }
        }, {description: "Cancel active voice input"})
    }
}
