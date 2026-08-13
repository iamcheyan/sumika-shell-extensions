import qs
import qs.modules.common
import qs.modules.keyboardremap
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings
import qs.modules.settings.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: pageRoot

    required property var settingsRoot
    readonly property bool wideLayout: width >= 980
    property bool restoringAfterFunctionRowAuth: false

    function applyFunctionRowMode(value) {
        if (KeyboardRemap.functionRowBusy || value === KeyboardRemap.functionRowMode)
            return
        pageRoot.restoringAfterFunctionRowAuth = true
        pageRoot.settingsRoot.show = false
        Qt.callLater(() => KeyboardRemap.setFunctionRowMode(value))
    }

    // Footer contract (Discard / Apply)
    readonly property bool hasPendingChanges: KeyboardRemap.hasPendingChanges
    readonly property bool applying: KeyboardRemap.applyInProgress
    function resetDrafts() {
        KeyboardRemap.loadProfiles()
        KeyboardRemap.checkPendingChanges()
    }
    function applyAll() {
        if (!KeyboardRemap.hasPendingChanges || KeyboardRemap.applyInProgress)
            return
        KeyboardRemap.apply()
    }

    readonly property bool showList: pageRoot.wideLayout
        || !pageRoot.settingsRoot.keyremapDetailOpen
        || KeyboardRemap.selectedDeviceId === ""
    readonly property bool showDetail: pageRoot.wideLayout
        ? KeyboardRemap.selectedDeviceId !== ""
        : (pageRoot.settingsRoot.keyremapDetailOpen && KeyboardRemap.selectedDeviceId !== "")

    readonly property string healthTitle: {
        if (KeyboardRemap.state === "setup")
            return "Needs setup"
        if (!KeyboardRemap.keydReady)
            return "keyd not ready"
        if (KeyboardRemap.hasPendingChanges)
            return "Pending changes"
        return "Ready"
    }
    readonly property string healthDetail: {
        const n = KeyboardRemap.availableDevices.length
        const devices = `${n} keyboard${n === 1 ? "" : "s"}`
        if (KeyboardRemap.lastError.length > 0)
            return KeyboardRemap.lastError
        if (KeyboardRemap.hasPendingChanges)
            return `${devices} · draft not applied yet`
        if (KeyboardRemap.keydReady)
            return `${devices} · config matches this page`
        return `${devices} · check keyd service`
    }
    readonly property bool healthWarning: !KeyboardRemap.keydReady
        || KeyboardRemap.state === "setup"
        || KeyboardRemap.lastError.length > 0
    readonly property string selectedDisplayName: KeyboardRemap.selectedProfile?.displayName
        ?? KeyboardRemap.selectedDevice?.displayName
        ?? KeyboardRemap.selectedDeviceId
        ?? "Keyboard"
    readonly property string selectedKeydId: KeyboardRemap.selectedDevice?.keydId
        || KeyboardRemap.selectedProfile?.keydId
        || ""
    readonly property int selectedPresetCount: KeyboardRemap.devicePresetCount(KeyboardRemap.selectedDeviceId)
    readonly property bool selectedConnected: KeyboardRemap.selectedDevice?.connected === true

    width: parent ? parent.width : 900
    spacing: SettingsTokens.controlGap
    implicitHeight: {
        const viewportHeight = pageRoot.settingsRoot ? pageRoot.settingsRoot.height - 120 : 500
        return Math.max(420, viewportHeight)
    }

    function openDevice(hyprName) {
        KeyboardRemap.selectDevice(hyprName)
        pageRoot.settingsRoot.keyremapDetailOpen = true
    }

    function closeDetail() {
        pageRoot.settingsRoot.keyremapDetailOpen = false
        pageRoot.settingsRoot.keyremapEditingPreset = ""
    }

    function refreshPage() {
        KeyboardRemap.refreshDevices()
        KeyboardRemap.loadProfiles()
        KeyboardRemap.checkKeyd()
        KeyboardRemap.checkPendingChanges()
        KeyboardRemap.refreshFunctionRow()
    }

    GridLayout {
        id: contentGrid
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: pageRoot.wideLayout ? 2 : 1
        columnSpacing: SettingsTokens.columnGap
        rowSpacing: SettingsTokens.columnGap

        // ════════════════════════════════════════
        // LEFT · Status & keyboards
        // ════════════════════════════════════════
        Rectangle {
            visible: pageRoot.showList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: pageRoot.wideLayout
                ? (contentGrid.width - SettingsTokens.columnGap) / 2
                : contentGrid.width
            Layout.minimumHeight: 320
            radius: SettingsTokens.roundRadius
            color: SettingsTokens.panel
            border.width: 1
            border.color: SettingsTokens.line

            ColumnLayout {
                id: leftColumn
                anchors.fill: parent
                anchors.margins: SettingsTokens.panelPadding
                spacing: SettingsTokens.sectionGap

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 68

                    RowLayout {
                        anchors.fill: parent
                        spacing: 14

                        Rectangle {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            radius: SettingsTokens.radius
                            color: pageRoot.healthWarning ? SettingsTokens.warningPanel : SettingsTokens.accentSoft
                            border.width: pageRoot.healthWarning ? 1 : 0
                            border.color: pageRoot.healthWarning ? SettingsTokens.warningBorder : "transparent"

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: pageRoot.healthWarning ? "warning" : "keyboard"
                                iconSize: 25
                                color: pageRoot.healthWarning ? SettingsTokens.danger : SettingsTokens.accent
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            StyledText {
                                Layout.fillWidth: true
                                text: "Keyboard remap"
                                color: SettingsTokens.fg
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: `${pageRoot.healthTitle}  ·  ${pageRoot.healthDetail}`
                                color: pageRoot.healthWarning ? SettingsTokens.danger : SettingsTokens.muted
                                font.pixelSize: Appearance.font.pixelSize.small
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: SettingsTokens.line
                }

                SettingsSection {
                    visible: KeyboardRemap.functionRowAvailable
                    title: "MacBook function row"

                    SettingsDropdownRow {
                        label: "Top-row key behavior"
                        description: KeyboardRemap.functionRowBusy
                            ? "Applying system keyboard setting…"
                            : "Choose whether media controls or F1–F12 work without Fn."
                        currentValue: KeyboardRemap.functionRowMode
                        controlled: true
                        dropdownWidth: 190
                        options: [
                            { label: "Media controls first", value: "media" },
                            { label: "F1–F12 first", value: "function" },
                            { label: "Automatic", value: "auto" }
                        ]
                        onValueChanged: value => pageRoot.applyFunctionRowMode(value)
                    }

                    StyledText {
                        visible: KeyboardRemap.functionRowError.length > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: KeyboardRemap.functionRowError
                        color: SettingsTokens.danger
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.WordWrap
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 4
                    Layout.leftMargin: 4
                    text: "Keyboards"
                    color: SettingsTokens.muted
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                StyledFlickable {
                    id: keyboardListFlickable
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: keyboardListColumn.implicitHeight

                    ColumnLayout {
                        id: keyboardListColumn
                        width: keyboardListFlickable.width
                        spacing: 2

                        Repeater {
                            model: KeyboardRemap.availableDevices
                            delegate: Rectangle {
                                id: deviceRow
                                required property var modelData
                                readonly property int presetCount: KeyboardRemap.devicePresetCount(modelData.hyprName)
                                readonly property bool selected: modelData.hyprName === KeyboardRemap.selectedDeviceId
                                readonly property bool currentConnected: deviceRow.selected && modelData.connected

                                Layout.fillWidth: true
                                implicitHeight: deviceRow.selected ? 66 : 56
                                radius: SettingsTokens.radius
                                color: deviceRow.selected
                                    ? (deviceRow.currentConnected ? SettingsTokens.accentSoft : SettingsTokens.panelAlt)
                                    : (deviceMouse.containsMouse ? SettingsTokens.cardHover : "transparent")
                                border.width: deviceRow.selected ? 1 : 0
                                border.color: deviceRow.currentConnected ? SettingsTokens.accent : SettingsTokens.line

                                Rectangle {
                                    visible: deviceRow.selected
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 4
                                    radius: 2
                                    color: deviceRow.currentConnected ? SettingsTokens.accent : SettingsTokens.muted
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: deviceRow.selected ? 16 : 12
                                    anchors.rightMargin: 12
                                    spacing: 12

                                    MaterialSymbol {
                                        Layout.preferredWidth: 22
                                        text: "keyboard"
                                        iconSize: 18
                                        color: deviceRow.currentConnected ? SettingsTokens.accent : SettingsTokens.muted
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: deviceRow.modelData.displayName
                                            color: SettingsTokens.fg
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: deviceRow.selected ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            StyledText {
                                                visible: deviceRow.modelData.main
                                                text: "Main"
                                                color: SettingsTokens.accent
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                            }

                                            StyledText {
                                                text: deviceRow.modelData.connected
                                                    ? `${deviceRow.modelData.layout} · ${deviceRow.modelData.keydId}`
                                                    : "Disconnected"
                                                color: deviceRow.modelData.connected ? SettingsTokens.muted : SettingsTokens.danger
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.preferredWidth: deviceRow.selected ? 60 : 0
                                        Layout.fillHeight: true
                                        clip: true
                                        opacity: deviceRow.selected ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 100 } }

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            visible: deviceRow.selected

                                            Rectangle {
                                                width: 28; height: 28; radius: SettingsTokens.radius
                                                color: deleteMouse.containsMouse ? SettingsTokens.buttonHover : "transparent"
                                                visible: !deviceRow.currentConnected

                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "delete"
                                                    iconSize: 16
                                                    color: SettingsTokens.danger
                                                }
                                                MouseArea {
                                                    id: deleteMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: KeyboardRemap.deleteProfile(deviceRow.modelData.hyprName)
                                                }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: deviceMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pageRoot.openDevice(deviceRow.modelData.hyprName)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ════════════════════════════════════════
        // RIGHT · Device detail & presets
        // ════════════════════════════════════════
        Rectangle {
            visible: pageRoot.showDetail
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: pageRoot.wideLayout
                ? (contentGrid.width - SettingsTokens.columnGap) / 2
                : contentGrid.width
            Layout.minimumHeight: 320
            radius: SettingsTokens.roundRadius
            color: SettingsTokens.panel
            border.width: 1
            border.color: SettingsTokens.line

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: SettingsTokens.panelPadding
                spacing: SettingsTokens.sectionGap

                // Header with back/close
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: SettingsTokens.radius
                        color: backMouse.containsMouse ? SettingsTokens.buttonHover : "transparent"
                        visible: !pageRoot.wideLayout

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            iconSize: 20
                            color: SettingsTokens.fg
                        }
                        MouseArea {
                            id: backMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pageRoot.closeDetail()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: pageRoot.selectedDisplayName
                            color: SettingsTokens.fg
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: pageRoot.selectedKeydId
                                ? `${pageRoot.selectedKeydId}  ·  ${pageRoot.selectedPresetCount} preset${pageRoot.selectedPresetCount === 1 ? "" : "s"}`
                                : "No keyd ID — profile cannot be applied"
                            color: pageRoot.selectedKeydId ? SettingsTokens.muted : SettingsTokens.danger
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: SettingsTokens.radius
                        color: closeMouse.containsMouse ? SettingsTokens.buttonHover : "transparent"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 20
                            color: SettingsTokens.muted
                        }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pageRoot.closeDetail()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: SettingsTokens.line
                }

                // Presets list
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        text: "Presets"
                        color: SettingsTokens.muted
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        text: "(conflicting presets auto-exclude each other)"
                        color: SettingsTokens.dim
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: SettingsTokens.radius
                        color: enableMouse.containsMouse ? SettingsTokens.buttonHover : "transparent"
                        visible: KeyboardRemap.selectedDeviceId !== ""

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: KeyboardRemap.selectedEnabled ? "toggle_on" : "toggle_off"
                            iconSize: 22
                            color: KeyboardRemap.selectedEnabled ? SettingsTokens.accent : SettingsTokens.muted
                        }
                        MouseArea {
                            id: enableMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: KeyboardRemap.setProfileEnabled(!KeyboardRemap.selectedEnabled)
                        }
                    }
                }

                Repeater {
                    model: KeyboardRemap.globalPresetChoices
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property string deviceId: KeyboardRemap.selectedDeviceId
                        readonly property bool enabled: deviceId !== ""
                            && KeyboardRemap.selectedEnabled
                            && KeyboardRemap.devicePresetEnabled(deviceId, modelData.id)
                        readonly property bool canToggle: deviceId !== ""
                            && KeyboardRemap.selectedEnabled

                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: SettingsTokens.radius
                        color: enabled
                            ? SettingsTokens.accentSoft
                            : (presetMouse.containsMouse && canToggle ? SettingsTokens.cardHover : "transparent")
                        border.width: enabled ? 1 : 0
                        border.color: enabled ? SettingsTokens.accent : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: SettingsTokens.fg
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: enabled ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.description
                                    color: SettingsTokens.muted
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }

                            MaterialSymbol {
                                visible: modelData.type === "remap"
                                text: "edit"
                                iconSize: 18
                                color: presetEditMouse.containsMouse ? SettingsTokens.accent : SettingsTokens.muted
                                MouseArea {
                                    id: presetEditMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        pageRoot.settingsRoot.keyremapEditingPreset = modelData.id
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: presetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: canToggle
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                KeyboardRemap.setDevicePresetEnabled(deviceId, modelData.id, !enabled)
                            }
                        }
                    }
                }
            }
        }
    }
}
