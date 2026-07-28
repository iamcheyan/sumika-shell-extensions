pragma ComponentBehavior: Bound
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

ManagedPopupWindow {
    id: root

    property string shareDir: FileUtils.trimFileProtocol(Qt.resolvedUrl("..")) + "/bin"

    readonly property int itemHeight: 32
    readonly property int indicatorSize: 16
    readonly property real hPadding: 10

    // ── Model status state ──
    property string modelStatus: "checking"
    property string modelSize: ""
    property string venvStatus: "checking"
    property string daemonStatus: "checking"
    property bool downloadRunning: false

    // Override open/close to manage barPopupType
    function open() {
        root.visible = true;
        GlobalStates.barPopupType = "voiceModel";
    }
    function close() {
        if (GlobalStates.barPopupType === "voiceModel")
            GlobalStates.barPopupType = "";
        root.popupClosed();
    }

    Component.onCompleted: {
        open();
        refreshAll();
    }

    function refreshAll() {
        modelStatus = "checking";
        venvStatus = "checking";
        daemonStatus = "checking";
        checkModelProc.running = true;
    }

    function indicator(status) {
        if (status === "ok") return "●"
        if (status === "missing") return "●"
        if (status === "checking") return "●"
        return "●"
    }

    function indicatorColor(status) {
        if (status === "ok") return "#4CAF50"
        if (status === "missing") return "#FF5252"
        if (status === "checking") return "#FFC107"
        return "#FF5252"
    }

    // ── Model file check ──
    Process {
        id: checkModelProc
        command: ["bash", "-c",
            `if [ -f '${FileUtils.trimFileProtocol(Directories.genericCache)}/sumika-voice/sense-voice-small-int8/model.int8.onnx' ]; then size=$(du -sm '${FileUtils.trimFileProtocol(Directories.genericCache)}/sumika-voice/sense-voice-small-int8' 2>/dev/null | awk '{print $1}'); echo "ok:$size"; else echo "missing"; fi`]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("ok:")) {
                    root.modelStatus = "ok"
                    root.modelSize = line.substring(3) + " MB"
                } else {
                    root.modelStatus = "missing"
                    root.modelSize = ""
                }
            }
        }
        onExited: (code, status) => {
            venvCheckProc.running = true
        }
    }

    // ── Venv check ──
    Process {
        id: venvCheckProc
        command: ["bash", "-c",
            `if [ -f '${FileUtils.trimFileProtocol(Directories.genericCache)}/sumika-voice/venv/bin/python3' ]; then echo ok; else echo missing; fi`]
        stdout: SplitParser {
            onRead: (line) => {
                root.venvStatus = line === "ok" ? "ok" : "missing"
            }
        }
        onExited: (code, status) => {
            daemonCheckProc.running = true
        }
    }

    // ── Daemon check ──
    Process {
        id: daemonCheckProc
        command: ["bash", "-c",
            `if [ -S /tmp/sumika-voice.sock ] && ss -xl src /tmp/sumika-voice.sock 2>/dev/null | grep -q LISTEN; then echo running; else echo idle; fi`]
        stdout: SplitParser {
            onRead: (line) => {
                root.daemonStatus = line === "running" ? "ok" : "idle"
            }
        }
    }

    Connections {
        target: GlobalStates
        function onBarPopupTypeChanged() {
            if (GlobalStates.barPopupType !== "voiceModel" && root.visible) {
                root.close();
            }
        }
    }

    // ── Content (fed to ManagedPopupWindow's default property) ──

    // Title
    Item {
        Layout.fillWidth: true
        implicitHeight: root.itemHeight
        StyledText {
            anchors.centerIn: parent
            text: "Offline Model Status"
            color: TuiStyle.fg
            font { pixelSize: 14; weight: Font.Medium }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: TuiStyle.line
        opacity: TuiStyle.dividerOpacity
        Layout.topMargin: 2
        Layout.bottomMargin: 6
    }

    // ── Status rows ──
    component StatusRow : Item {
        property string label: ""
        property string status: "checking"
        property string detail: ""

        implicitHeight: root.itemHeight
        Layout.fillWidth: true

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.hPadding
            anchors.rightMargin: root.hPadding
            spacing: 8

            StyledText {
                text: root.indicator(parent.parent.status)
                color: root.indicatorColor(parent.parent.status)
                font.pixelSize: root.indicatorSize
                Layout.preferredWidth: root.indicatorSize
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: parent.parent.label
                color: TuiStyle.fg
                font.pixelSize: 13
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: parent.parent.detail
                color: TuiStyle.fgSub
                font.pixelSize: 12
                visible: parent.parent.detail.length > 0
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    StatusRow {
        label: "Model File (SenseVoice)"
        status: root.modelStatus
        detail: root.modelSize
    }

    StatusRow {
        label: "Python Virtual Environment"
        status: root.venvStatus
        detail: root.venvStatus === "ok" ? "Ready" : ""
    }

    StatusRow {
        label: "Voice Daemon"
        status: root.daemonStatus
        detail: root.daemonStatus === "ok" ? "Running" : root.daemonStatus === "idle" ? "Auto-start on use" : ""
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: TuiStyle.line
        opacity: TuiStyle.dividerOpacity
        Layout.topMargin: 6
        Layout.bottomMargin: 4
    }

    // ── Action buttons ──
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        Layout.bottomMargin: 2
        spacing: 6

        Item { Layout.fillWidth: true }

        RippleButton {
            id: downloadBtn
            enabled: !root.downloadRunning
            implicitHeight: root.itemHeight
            implicitWidth: 120
            buttonRadius: 6
            horizontalPadding: root.hPadding
            colBackground: "transparent"
            colBackgroundHover: TuiStyle.surfaceHover
            colRipple: TuiStyle.surfacePressed
            borderWidth: 1
            borderColor: TuiStyle.panelAlt

            contentItem: StyledText {
                anchors.centerIn: parent
                text: root.downloadRunning ? "Downloading…" : "Redownload"
                color: downloadBtn.enabled ? TuiStyle.fg : TuiStyle.fgSub
                font.pixelSize: 13
            }

            onClicked: {
                root.downloadRunning = true;
                root.modelStatus = "checking";
                root.venvStatus = "checking";
                root.daemonStatus = "checking";
                Quickshell.execDetached(["bash", "-c", `"${root.shareDir}/sumika-voice-setup" && "${root.shareDir}/sumika-voice-download"`]);
                refreshTimer.restart();
            }
        }

        RippleButton {
            implicitHeight: root.itemHeight
            implicitWidth: 80
            buttonRadius: 6
            horizontalPadding: root.hPadding
            colBackground: "transparent"
            colBackgroundHover: TuiStyle.surfaceHover
            colRipple: TuiStyle.surfacePressed
            borderWidth: 1
            borderColor: TuiStyle.panelAlt

            contentItem: StyledText {
                anchors.centerIn: parent
                text: "Refresh"
                color: TuiStyle.fg
                font.pixelSize: 13
            }

            onClicked: root.refreshAll()
        }
        RippleButton {
            implicitHeight: root.itemHeight
            implicitWidth: 120
            buttonRadius: 6
            horizontalPadding: root.hPadding
            colBackground: "transparent"
            colBackgroundHover: TuiStyle.surfaceHover
            colRipple: TuiStyle.surfacePressed
            borderWidth: 1
            borderColor: TuiStyle.panelAlt

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.hPadding
                anchors.rightMargin: root.hPadding
                spacing: 6
                StyledText {
                    text: NerdIconMap.keyboard
                    color: TuiStyle.fg
                    font.pixelSize: 14
                    Layout.alignment: Qt.AlignVCenter
                }
                StyledText {
                    text: "Edit Hotkeys"
                    color: TuiStyle.fg
                    font.pixelSize: 13
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            onClicked: {
                root.close();
                Quickshell.execDetached(["bash", "-c",
                    `"${FileUtils.trimFileProtocol(Qt.resolvedUrl(".."))}/bin/sumika-edit-voice-bindings"`]);
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 5000
        repeat: false
        onTriggered: {
            root.downloadRunning = false;
            root.refreshAll();
        }
    }
}
