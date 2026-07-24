import qs
import qs.modules.voice
import qs.modules.bar
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import QtQuick.Layouts

Item {
    id: root

    implicitWidth: Config.options.bar.rightIconSlotWidth
    implicitHeight: Config.options.bar.rightIconSlotWidth
    Layout.fillHeight: true

    // Voice input state
    readonly property string voiceState: VoiceInput.state
    readonly property bool isRecording: voiceState === "recording"
    readonly property bool isTranscribing: voiceState === "transcribing"
    readonly property bool isSetup: voiceState === "setup"
    readonly property bool isError: voiceState === "error"
    readonly property bool isActive: isRecording || isTranscribing || isSetup

    readonly property color colorIdle: Appearance.colors.colBarText
    readonly property color colorRecording: "#F5C542"
    readonly property color colorTranscribing: "#5B9BD5"
    readonly property color colorError: "#FF3B30"

    readonly property color iconColor: {
        if (root.isError) return root.colorError
        if (root.isRecording) return root.colorRecording
        if (root.isTranscribing) return root.colorTranscribing
        if (root.isSetup) return root.colorRecording
        return root.colorIdle
    }

    readonly property string iconText: {
        if (root.isTranscribing) return NerdIconMap.hourglass
        if (root.isActive) return NerdIconMap.mic
        return NerdIconMap.mic
    }

    RippleButton {
        id: button
        anchors.centerIn: parent
        width: Config.options.bar.rightIconSlotWidth
        height: Config.options.bar.rightIconSlotWidth
        buttonRadius: Config.options.bar.rightIconSlotWidth / 2
        colBackground: "transparent"
        colBackgroundHover: Qt.rgba(1, 1, 1, 0.10)
        colBackgroundToggled: Qt.rgba(1, 1, 1, 0.18)
        colBackgroundToggledHover: Qt.rgba(1, 1, 1, 0.26)
        colRipple: Qt.rgba(1, 1, 1, 0.12)
        colRippleToggled: Qt.rgba(1, 1, 1, 0.18)
        toggled: GlobalStates.barPopupType === "voice"

        onClicked: {
            if (Date.now() - GlobalStates.barPopupDismissedAt < 200)
                return;
            VoiceInput.toggle();
            GlobalStates.barPopupType = GlobalStates.barPopupType === "voice"
                ? ""
                : "voice";
        }

        // Right click: show model status popup
        altAction: function(event) {
            statusPopupLoader.active = true;
        }
    }

    // Pulse ring for recording/transcribing
    Rectangle {
        id: pulseRing
        anchors.centerIn: button
        width: button.width
        height: button.height
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: root.isRecording ? root.colorRecording
            : root.isTranscribing ? root.colorTranscribing
            : root.colorRecording
        visible: root.isActive
        opacity: 0.75

        SequentialAnimation on scale {
            running: root.isRecording
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 1.65; duration: 750; easing.type: Easing.OutCubic }
            NumberAnimation { from: 1.65; to: 1.0; duration: 0 }
        }
        SequentialAnimation on opacity {
            running: root.isRecording
            loops: Animation.Infinite
            NumberAnimation { from: 0.75; to: 0; duration: 750; easing.type: Easing.OutCubic }
            NumberAnimation { from: 0; to: 0.75; duration: 0 }
        }
    }

    BarNerdIcon {
        id: icon
        anchors.centerIn: button
        iconSize: root.isTranscribing
            ? Config.options.bar.rightIconSize * 0.72
            : Config.options.bar.rightIconSize
        text: root.iconText
        color: root.iconColor

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    // Recording blink animation
    SequentialAnimation {
        id: recordingBlink
        running: false
        loops: 2
        NumberAnimation { target: icon; property: "opacity"; from: 1.0; to: 0.3; duration: 500 }
        NumberAnimation { target: icon; property: "opacity"; from: 0.3; to: 1.0; duration: 500 }
        onStopped: icon.opacity = 1.0
    }

    // Transcribing rotation animation
    SequentialAnimation {
        id: rotateAnim
        running: root.isTranscribing
        loops: Animation.Infinite
        NumberAnimation {
            target: icon
            property: "rotation"
            from: 0
            to: 180
            duration: 2000
            easing.type: Easing.InOutQuad
        }
        PauseAnimation { duration: 300 }
        PropertyAction {
            target: icon
            property: "rotation"
            value: 0
        }
        onStopped: icon.rotation = 0
    }

    onIsErrorChanged: {
        if (root.isError)
            recordingBlink.start();
    }
    // Right-click: model status popup
    Loader {
        id: statusPopupLoader
        active: false
        source: "VoiceModelStatusPopup.qml"
        onLoaded: {
            const a = item.anchor;
            a.window = root.QsWindow.window;
            a.item = button;
            a.gravity = Config.options.bar.vertical
                ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom);
            a.edges = Config.options.bar.vertical
                ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom);
            item.open();
            item.closed.connect(() => statusPopupLoader.active = false);
        }
    }
}
