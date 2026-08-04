import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

Item {
    id: root

    // True while a screen recording is in progress. Polled only during a
    // screenshot/recording session (screenshotActive) to avoid overhead.
    property bool recordingActive: false

    // Poll the recorder pid file while a screenshot session is active.
    Timer {
        interval: 1500
        repeat: true
        running: GlobalStates.screenshotActive
        onTriggered: recordCheckProc.running = true
        // The selector closes as soon as Stop is pressed, which disables this
        // timer before another poll can clear the old value.
        onRunningChanged: {
            if (!running)
                root.recordingActive = false;
        }
    }
    Process {
        id: recordCheckProc
        command: ["bash", "-c",
            "pidfile=\"${XDG_RUNTIME_DIR:-/tmp}/sumika-record.pid\"; " +
            "[ -f \"$pidfile\" ] && kill -0 \"$(cat \"$pidfile\")\" 2>/dev/null && echo yes || echo no"]
        stdout: SplitParser {
            onRead: line => root.recordingActive = (line.trim() === "yes")
        }
    }

    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    Layout.fillHeight: true
    implicitWidth: Config.options.bar.rightIconSlotWidth
    implicitHeight: Config.options.bar.rightIconSlotWidth

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

        onClicked: {
            // Left click: quick screenshot (default action)
            Quickshell.execDetached(["sumika-screenshot"]);
        }

        // Right click: open context menu
        altAction: function(event) {
            menuLoader.open();
        }
    }

    BarNerdIcon {
        anchors.centerIn: button
        text: NerdIconMap.camera
        color: Appearance.colors.colBarText
    }

    // Pulsing red dot at the icon's bottom-right while recording.
    Rectangle {
        visible: GlobalStates.screenshotActive && root.recordingActive
        anchors.right: button.right
        anchors.bottom: button.bottom
        anchors.margins: 3
        width: 11; height: 11; radius: 5.5
        color: "#e53935"
        border.width: 1.5
        border.color: Appearance.colors.colBarBg ?? "#000000"
        z: 10
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.25; duration: 700 }
            NumberAnimation { from: 0.25; to: 1; duration: 700 }
        }
    }

    BarContextMenu {
        id: menuLoader
        anchorItem: button
        sourceComponent: ScreenshotContextMenu {}
    }
}
