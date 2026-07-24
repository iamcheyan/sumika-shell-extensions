pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

PopupWindow {
    id: root

    property string shareDir: FileUtils.trimFileProtocol(Qt.resolvedUrl("..")) + "/bin"
    signal closed()

    color: "transparent"

    readonly property int itemHeight: 32
    readonly property int indicatorSize: 16
    readonly property real hPadding: 10
    readonly property real menuPadding: 6
    readonly property real outerPadding: Appearance.sizes.elevationMargin

    implicitWidth: popupBackground.implicitWidth + root.outerPadding * 2
    implicitHeight: popupBackground.implicitHeight + root.outerPadding * 2

    // ── Model status state ──
    property string modelStatus: "checking"
    property string modelSize: ""
    property string venvStatus: "checking"
    property string daemonStatus: "checking"
    property bool downloadRunning: false

    function open() { root.visible = true }
    function close() {
        root.visible = false;
        root.closed();
    }

    Component.onCompleted: {
        root.visible = true;
        refreshAll();
    }
    Component.onDestruction: {
        dismissGuard.stop();
        GlobalFocusGrab.removeDismissable(root);
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
            `if [ -f '${FileUtils.trimFileProtocol(Directories.genericCache)}/omd-voice/sense-voice-small-int8/model.int8.onnx' ]; then size=$(du -sm '${FileUtils.trimFileProtocol(Directories.genericCache)}/omd-voice/sense-voice-small-int8' 2>/dev/null | awk '{print $1}'); echo "ok:$size"; else echo "missing"; fi`]
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
            `if [ -f '${FileUtils.trimFileProtocol(Directories.genericCache)}/omd-voice/venv/bin/python3' ]; then echo ok; else echo missing; fi`]
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
            `if [ -S /tmp/omd-voice.sock ] && ss -x src /tmp/omd-voice.sock 2>/dev/null | grep -q LISTEN; then echo ok; else echo missing; fi`]
        stdout: SplitParser {
            onRead: (line) => {
                root.daemonStatus = line === "ok" ? "ok" : "missing"
            }
        }
    }

    Timer {
        id: dismissGuard
        interval: 180
        repeat: false
        onTriggered: {
            if (root.visible)
                GlobalFocusGrab.addDismissable(root);
        }
    }

    onVisibleChanged: {
        if (visible) {
            dismissGuard.restart();
        } else {
            dismissGuard.stop();
            GlobalFocusGrab.removeDismissable(root);
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            root.close()
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onPressed: event => {
            const pos = mapToItem(popupBackground, event.x, event.y)
            if (pos.x < 0 || pos.x > popupBackground.width || pos.y < 0 || pos.y > popupBackground.height)
                root.close();
        }

        StyledRectangularShadow {
            target: popupBackground
            opacity: popupBackground.opacity
        }

        Rectangle {
            id: popupBackground
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: root.outerPadding
            }
            color: TuiStyle.bg
            radius: TuiStyle.shellRadius
            border.width: TuiStyle.borderWidth
            border.color: TuiStyle.menuBorder
            clip: true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: popupBackground.width
                    height: popupBackground.height
                    radius: popupBackground.radius
                }
            }

            opacity: 0
            Component.onCompleted: opacity = 1
            implicitWidth: columnLayout.implicitWidth + root.menuPadding * 2
            implicitHeight: columnLayout.implicitHeight + root.menuPadding * 2

            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(popupBackground) }
            Behavior on implicitHeight { animation: Appearance.animation.elementResize.numberAnimation.createObject(popupBackground) }
            Behavior on implicitWidth { animation: Appearance.animation.elementResize.numberAnimation.createObject(popupBackground) }

            ColumnLayout {
                id: columnLayout
                anchors {
                    fill: parent
                    margins: root.menuPadding
                }
                spacing: 0

                // Title
                Item {
                    Layout.fillWidth: true
                    implicitHeight: root.itemHeight
                    StyledText {
                        anchors.centerIn: parent
                        text: "离线模型状态"
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
                    label: "模型文件 (SenseVoice)"
                    status: root.modelStatus
                    detail: root.modelSize
                }

                StatusRow {
                    label: "Python 虚拟环境"
                    status: root.venvStatus
                    detail: root.venvStatus === "ok" ? "已就绪" : ""
                }

                StatusRow {
                    label: "语音守护进程"
                    status: root.daemonStatus
                    detail: root.daemonStatus === "ok" ? "运行中" : ""
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
                            text: root.downloadRunning ? "下载中…" : "重新下载"
                            color: downloadBtn.enabled ? TuiStyle.fg : TuiStyle.fgSub
                            font.pixelSize: 13
                        }

                        onClicked: {
                            root.downloadRunning = true;
                            root.modelStatus = "checking";
                            root.venvStatus = "checking";
                            root.daemonStatus = "checking";
                            Quickshell.execDetached(["bash", "-c", `"${root.shareDir}/omd-voice-setup" && "${root.shareDir}/omd-voice-download"`]);
                            // Re-check after a delay
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
                            text: "刷新"
                            color: TuiStyle.fg
                            font.pixelSize: 13
                        }

                        onClicked: root.refreshAll()
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
                            text: "关闭"
                            color: TuiStyle.fg
                            font.pixelSize: 13
                        }

                        onClicked: root.close()
                    }
                }
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
