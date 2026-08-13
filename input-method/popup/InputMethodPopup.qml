import qs
import qs.modules.bar
import qs.modules.inputmethod as InputMethodMod
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core.runtime

PopupColumn {
    readonly property var im: InputMethodMod.InputMethod

    id: inputMethodPanel


    property var choices: [
        { schema: "sbzr", badge: "中", title: "Chinese", subtitle: "Natural input" },
        { schema: "sbzr_mix", badge: "混", title: "Chinese", subtitle: "Mixed input" },
        { schema: "easy_en", badge: "A", title: "English", subtitle: "Easy English" },
        { schema: "jaroomaji", badge: "あ", title: "Japanese", subtitle: "Romaji" }
    ]

    // ── Keyboard layout sub-view (二级弹出层) ──
    // Backed by bin/sumika-kb-layout: list / set XKB_DEFAULT_LAYOUT.
    property bool showLayouts: false
    property var layouts: []
    property string currentLayout: ""
    property string layoutsMessage: ""

    readonly property string kbLayoutBin: Directories.root + "/bin/sumika-kb-layout"
    readonly property var layoutNames: ({
        "us": "English",
        "us_intl": "English (Intl)",
        "gb": "English (UK)",
        "de": "German",
        "fr": "French",
        "ru": "Russian",
        "cn": "Chinese",
        "jp": "Japanese (JIS)"
    })

    function refreshLayouts() {
        layoutListProc.running = false;
        layoutListProc.running = true;
    }

    function applyLayout(code) {
        layoutSetProc.command = [inputMethodPanel.kbLayoutBin, "set", code];
        layoutSetProc.running = false;
        layoutSetProc.running = true;
    }

    Component.onCompleted: {
        im.refresh();
        refreshLayouts();
    }

    PopupHeader {
        Layout.fillWidth: true
        icon: NerdIconMap.keyboard
        title: "Input Language"
        subtitle: im.available ? im.summary : "Fcitx5 is unavailable"
        tone: im.available ? TuiStyle.accent : TuiStyle.danger
        showDivider: true
        leadingActionIcon: im.deploying ? "progress_activity" : "refresh"
        leadingActionTooltip: im.deploying ? "正在重新部署 Rime" : "重新部署 Rime"
        leadingActionEnabled: im.available && !im.busy && !im.deploying
        onLeadingActionClicked: im.redeployRime()
        middleActionIcon: "language"
        middleActionTooltip: inputMethodPanel.showLayouts ? "返回输入法" : "键盘布局"
        middleActionEnabled: im.available
        onMiddleActionClicked: inputMethodPanel.showLayouts = !inputMethodPanel.showLayouts
        actionIcon: "settings"
        actionTooltip: "输入法设置"
        onActionClicked: {
            GlobalStates.barPopupType = "";
            im.openConfiguration();
        }
    }

    Process {
        id: layoutListProc
        command: [inputMethodPanel.kbLayoutBin, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text);
                    inputMethodPanel.layouts = Array.isArray(arr) ? arr : [];
                    inputMethodPanel.currentLayout = inputMethodPanel.layouts.length > 0
                        ? inputMethodPanel.layouts[0] : "";
                    inputMethodPanel.layoutsMessage = "";
                } catch (e) {
                    inputMethodPanel.layouts = [];
                    inputMethodPanel.layoutsMessage = "无法读取键盘布局";
                }
            }
        }
    }

    Process {
        id: layoutSetProc
        command: [inputMethodPanel.kbLayoutBin, "set", "us"]
        stdout: StdioCollector {
            onStreamFinished: inputMethodPanel.refreshLayouts()
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                inputMethodPanel.layoutsMessage = "切换键盘布局失败";
        }
    }

    Repeater {
        model: inputMethodPanel.choices

        delegate: Rectangle {
            id: languageRow
            required property var modelData
            readonly property bool selected: im.schema === modelData.schema
            visible: !inputMethodPanel.showLayouts

            Layout.fillWidth: true
            Layout.preferredHeight: 58
            color: selected ? TuiStyle.panelAlt
                : languageMouse.containsMouse ? TuiStyle.surfaceHover
                : "transparent"
            radius: TuiStyle.miniRadius

            MouseArea {
                id: languageMouse
                anchors.fill: parent
                enabled: !im.busy
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const returnAddress = ServiceManager.workspace.activeWindow?.address || "";
                    GlobalStates.barPopupType = "";
                    im.selectSchema(languageRow.modelData.schema, returnAddress);
                }
            }

            Rectangle {
                id: languageBadge
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: TuiStyle.miniRadius
                color: languageRow.selected ? TuiStyle.accent : TuiStyle.surfaceSubtle

                StyledText {
                    anchors.centerIn: parent
                    text: languageRow.modelData.badge
                    color: languageRow.selected ? TuiStyle.bg : TuiStyle.fg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }

            Column {
                anchors.left: languageBadge.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                StyledText {
                    text: languageRow.modelData.title
                    color: TuiStyle.fg
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: languageRow.selected ? Font.DemiBold : Font.Normal
                }

                StyledText {
                    text: languageRow.modelData.subtitle
                    color: TuiStyle.dim
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

            NerdIcon {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                iconSize: 15
                text: im.busy && languageRow.selected
                    ? NerdIconMap.refresh
                    : NerdIconMap.check
                color: TuiStyle.accent
                visible: languageRow.selected
            }
        }
    }

    // ── Keyboard layout sub-view (二级弹出层) ──
    Rectangle {
        id: layoutBackRow
        visible: inputMethodPanel.showLayouts
        Layout.fillWidth: true
        Layout.preferredHeight: 48
        color: layoutBackMouse.containsMouse ? TuiStyle.surfaceHover : "transparent"
        radius: TuiStyle.miniRadius

        MouseArea {
            id: layoutBackMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: inputMethodPanel.showLayouts = false
        }

        NerdIcon {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            iconSize: 18
            text: NerdIconMap.chevronLeft
            color: TuiStyle.fg
        }

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: 46
            anchors.verticalCenter: parent.verticalCenter
            text: "键盘布局"
            color: TuiStyle.fg
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
        }

        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: inputMethodPanel.layoutsMessage
            color: TuiStyle.danger
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            visible: inputMethodPanel.layoutsMessage.length > 0
        }
    }

    Repeater {
        model: inputMethodPanel.layouts

        delegate: Rectangle {
            id: layoutRow
            required property string modelData
            readonly property bool selected: inputMethodPanel.currentLayout === modelData
            visible: inputMethodPanel.showLayouts

            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: selected ? TuiStyle.panelAlt
                : layoutMouse.containsMouse ? TuiStyle.surfaceHover
                : "transparent"
            radius: TuiStyle.miniRadius

            MouseArea {
                id: layoutMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: inputMethodPanel.applyLayout(layoutRow.modelData)
            }

            Rectangle {
                id: layoutBadge
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 30
                radius: TuiStyle.miniRadius
                color: layoutRow.selected ? TuiStyle.accent : TuiStyle.surfaceSubtle

                StyledText {
                    anchors.centerIn: parent
                    text: layoutRow.modelData.toUpperCase()
                    color: layoutRow.selected ? TuiStyle.bg : TuiStyle.fg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            StyledText {
                anchors.left: layoutBadge.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: inputMethodPanel.layoutNames[layoutRow.modelData] || layoutRow.modelData
                color: TuiStyle.fg
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: layoutRow.selected ? Font.DemiBold : Font.Normal
            }

            NerdIcon {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                iconSize: 15
                text: NerdIconMap.check
                color: TuiStyle.accent
                visible: layoutRow.selected
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        Layout.topMargin: 8
        Layout.bottomMargin: 8
        visible: inputMethodPanel.showLayouts && inputMethodPanel.layouts.length === 0
        text: "未配置键盘布局。请在 labwc/environment 的 XKB_DEFAULT_LAYOUT 中添加（如 us,jp）。"
        color: TuiStyle.dim
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
        wrapMode: Text.Wrap
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        Layout.topMargin: 8
        Layout.bottomMargin: 8
        visible: im.lastError.length > 0
        text: im.lastErrorTitle
        color: TuiStyle.danger
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
        wrapMode: Text.Wrap
    }
}
