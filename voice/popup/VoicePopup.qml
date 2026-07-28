import qs
import qs.services
import qs.modules.bar
import qs.modules.common
import qs.modules.voice
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

PopupColumn {
    id: voicePanel

    VoiceInput {
        id: vi
        visible: false
    }

    function stateLabel() {
        if (vi.state === "setup") return "Not Installed";
        if (vi.state === "idle") return "Ready";
        if (vi.state === "recording") return "Recording";
        if (vi.state === "transcribing") return "Transcribing";
        if (vi.state === "success") return "Transcription Success";
        if (vi.state === "error") return "Error";
        return vi.state;
    }
    function tone() {
        if (vi.state === "idle" || vi.state === "success") return TuiStyle.success;
        if (vi.state === "recording" || vi.state === "error") return TuiStyle.danger;
        if (vi.state === "transcribing" || vi.state === "setup") return TuiStyle.warning;
        return TuiStyle.muted;
    }

    PopupHeader {
        Layout.fillWidth: true
        icon: NerdIconMap.mic
        title: "Voice Input"
        subtitle: voicePanel.stateLabel()
        tone: voicePanel.tone()
    }

    // Model status card
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: modelCol.implicitHeight + 16
        color: TuiStyle.panel
        radius: TuiStyle.radius
        clip: true

        ColumnLayout {
            id: modelCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            PopupInfoRow {
                label: "Model"
                value: vi.modelSizeMB > 0 ? `SenseVoice Small (${vi.modelSizeMB} MB)` : "Missing"
                valueColor: vi.modelSizeMB > 0 ? TuiStyle.success : TuiStyle.danger
                showDivider: true
            }

            PopupInfoRow {
                label: "Daemon Status"
                value: vi.daemonRunning ? "Active (RAM Loaded)" : "Standby"
                valueColor: vi.daemonRunning ? TuiStyle.success : TuiStyle.dim
                showDivider: true
            }

            PopupInfoRow {
                label: "Virtual Env"
                value: vi.state === "setup" ? "Missing" : "Ready"
                valueColor: vi.state === "setup" ? TuiStyle.danger : TuiStyle.success
                showDivider: false
            }
        }
    }

    // Debug test section
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: debugCol.implicitHeight + 16
        color: TuiStyle.panel
        radius: TuiStyle.radius
        clip: true
        visible: vi.state !== "setup"

        ColumnLayout {
            id: debugCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Circle button for record toggle
                Rectangle {
                    id: debugRecBtn
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    radius: 24
                    color: vi.state === "recording" ? TuiStyle.danger : recMouse.containsMouse ? TuiStyle.surfaceHover : TuiStyle.surfaceRaised
                    border.width: 1
                    border.color: vi.state === "recording" ? TuiStyle.danger : TuiStyle.line

                    NerdIcon {
                        anchors.centerIn: parent
                        iconSize: 20
                        text: vi.state === "recording" ? NerdIconMap.stop : NerdIconMap.mic
                        color: vi.state === "recording" ? TuiStyle.fg : TuiStyle.fg
                    }

                    MouseArea {
                        id: recMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: vi.state === "idle" || vi.state === "recording"
                        onClicked: {
                            if (vi.state === "recording") {
                                vi.stopRecording();
                            } else {
                                vi.testRecording();
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: {
                            if (vi.state === "recording") return `Recording ${vi.recordingDuration.toFixed(1)}s`;
                            if (vi.state === "transcribing") return "Transcribing…";
                            if (vi.state === "success") return "Transcription ready";
                            if (vi.state === "error") return "Error";
                            return "Tap mic to test 3s";
                        }
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: voicePanel.tone()
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: vi.lastError || vi.lastTranscription || "—"
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: vi.lastError ? TuiStyle.danger : TuiStyle.fg
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                PopupIconButton {
                    label: "COPY TEXT"
                    enabledState: vi.lastTranscription.length > 0
                    onClicked: {
                        Quickshell.execDetached(["bash", "-c",
                            `printf '%s' '${StringUtils.shellSingleQuoteEscape(vi.lastTranscription)}' | wl-copy`]);
                        vi.notify("Copied", vi.lastTranscription, "edit-copy");
                    }
                }
                PopupIconButton {
                    label: "PASTE"
                    enabledState: vi.lastTranscription.length > 0
                    onClicked: {
                        Quickshell.execDetached(["bash", "-c",
                            `payload=$(mktemp); trap 'rm -f "$payload"' EXIT; ` +
                            `printf '%s' '${StringUtils.shellSingleQuoteEscape(vi.lastTranscription)}' > "$payload" && ` +
                            `wl-copy < "$payload" && SUMIKA_PASTE_SOURCE=voice-manual ` +
                            `'${vi.shareDir}/sumika-paste-at-cursor' --file "$payload" auto`]);
                    }
                }
            }
        }
    }

    // History section
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(historyList.implicitHeight + 16, 160)
        color: TuiStyle.panel
        radius: TuiStyle.radius
        clip: true
        visible: vi.history.length > 0

        ColumnLayout {
            id: historyList
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            StyledText {
                text: `History (${vi.history.length})`
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: TuiStyle.dim
            }

            ColumnLayout {
                spacing: 0
                Repeater {
                    model: vi.history.slice(0, 5)
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        color: histMouse.containsMouse ? TuiStyle.panelAlt : "transparent"

                        MouseArea {
                            id: histMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached(["bash", "-c",
                                    `printf '%s' '${StringUtils.shellSingleQuoteEscape(modelData.text)}' | wl-copy`]);
                                GlobalStates.barPopupType = "";
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: 8

                            StyledText {
                                text: modelData.time
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: TuiStyle.dim
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.text
                                elide: Text.ElideRight
                                font.family: Appearance.font.family.main
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: histMouse.containsMouse ? TuiStyle.fg : TuiStyle.muted
                            }
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        PopupIconButton {
            label: vi.state === "setup" ? "Setup" : "Test"
            onClicked: {
                if (vi.state === "setup") {
                    vi.setup();
                } else {
                    vi.testRecording();
                }
                GlobalStates.barPopupType = "";
            }
        }
        PopupIconButton {
            label: "Check State"
            onClicked: {
                vi.checkState();
                vi.refreshModelInfo();
                vi.refreshDaemonStatus();
            }
        }
        PopupIconButton {
            label: "Clear History"
            visible: vi.history.length > 0
            onClicked: vi.clearHistory()
        }
    }

    PopupFooterLink {
        Layout.fillWidth: true
        label: "Voice Settings…"
        onClicked: {
            GlobalStates.barPopupType = "";
            Quickshell.execDetached(["sumika-settings", "open", "voice"]);
        }
    }
}
