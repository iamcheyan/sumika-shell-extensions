import qs
import qs.services
import qs.modules.voice
import qs.modules.common
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
    readonly property string sumikaRoot: Directories.root
    readonly property string bindingsPath: `${FileUtils.trimFileProtocol(StandardPaths.home)}/.config/sumika-shell/voice/config.json`
    readonly property string translationHelper: FileUtils.trimFileProtocol(
        Qt.resolvedUrl("../bin/sumika-voice-translate"))
    readonly property string keyCaptureTool: `${
        Quickshell.env("SUMIKA_SHELL_EXTENSIONS_DIR")
            || FileUtils.trimFileProtocol(StandardPaths.home) + "/.local/share/sumika-shell/extensions"
    }/keyboard-remap/scripts/key-test-launcher`
    readonly property bool wideLayout: width >= 980

    property var voiceBindings: []
    property string bindingMessage: ""
    property bool capturingKey: false
    property string translationModel: ""
    property string translationTargetLanguage: "English"
    property string translationBinding: "HANGUL"
    property bool translationHasApiKey: false
    property bool translationReady: false
    property var translationModels: []
    property string openCodeConfigPath: ""
    property string translationMessage: ""

    width: parent ? parent.width : 900
    spacing: SettingsTokens.controlGap
    implicitHeight: {
        const viewportHeight = pageRoot.settingsRoot ? pageRoot.settingsRoot.height - 120 : 500
        const contentHeight = contentGrid.implicitHeight + 50 + spacing + 12
        return Math.max(viewportHeight, contentHeight)
    }

    // ── Health model ──
    readonly property bool needsSetup: VoiceInput.state === "setup" || VoiceInput.modelSizeMB === 0
    readonly property bool isRecording: VoiceInput.state === "recording"
    readonly property bool isTranscribing: VoiceInput.state === "transcribing"
        || VoiceInput.state === "translating"
    readonly property bool isError: VoiceInput.state === "error"
    readonly property string healthTitle: {
        if (pageRoot.needsSetup)
            return "Needs setup"
        if (pageRoot.isRecording)
            return VoiceInput.activeMode === "translation"
                ? `Recording for ${VoiceInput.translationTargetLanguage}…`
                : "Recording…"
        if (VoiceInput.state === "translating")
            return `Translating to ${VoiceInput.translationTargetLanguage}…`
        if (pageRoot.isTranscribing)
            return "Transcribing…"
        if (pageRoot.isError)
            return "Error"
        if (VoiceInput.state === "success")
            return "Done"
        return "Ready"
    }
    readonly property string healthDetail: {
        const modelPart = VoiceInput.modelSizeMB > 0
            ? `SenseVoice · ${VoiceInput.modelSizeMB} MB`
            : "Model missing"
        if (pageRoot.needsSetup)
            return `${modelPart} · run setup to enable voice input`
        const daemonPart = VoiceInput.daemonRunning ? "daemon running" : "daemon idle"
        if (pageRoot.isRecording)
            return `${modelPart} · ${VoiceInput.recordingDuration.toFixed(1)}s`
        return `${modelPart} · ${daemonPart}`
    }
    readonly property string healthIcon: {
        if (pageRoot.needsSetup)
            return "download"
        if (pageRoot.isRecording)
            return "mic"
        if (pageRoot.isTranscribing)
            return "hourglass_empty"
        if (pageRoot.isError)
            return "error"
        return "keyboard_voice"
    }
    readonly property bool healthWarning: pageRoot.needsSetup || pageRoot.isError

    function friendlyBinding(raw) {
        const key = (raw || "").trim()
        if (key.length === 0)
            return ""
        const map = {
            "ALT + A": "Alt + A",
            "code:472": "Globe (Fn)",
            "HANGUL_HANJA": "Hangul / Hanja",
            "XF86Tools": "F13 / Tools",
            "TOOLS": "F13 / Tools",
            "0X100811D0": "Hangul / Hanja",
            "0x100811D0": "Hangul / Hanja",
            "escape": "Esc",
            "ESCAPE": "Esc"
        }
        if (map[key])
            return map[key]
        if (key.toLowerCase().startsWith("code:"))
            return `Keycode ${key.slice(5)}`
        return key
            .replace(/\bALT\b/g, "Alt")
            .replace(/\bCTRL\b/g, "Ctrl")
            .replace(/\bCONTROL\b/g, "Ctrl")
            .replace(/\bSUPER\b/g, "Super")
            .replace(/\bSHIFT\b/g, "Shift")
            .replace(/\bMOD\b/g, "Mod")
    }

    function refreshBindings() {
        voiceBindingsProc.running = true
    }

    function removeBinding(raw) {
        const target = (raw || "").trim()
        if (target.length === 0)
            return
        const next = pageRoot.voiceBindings.filter(b => b !== target)
        if (next.length === pageRoot.voiceBindings.length)
            return
        pageRoot.voiceBindings = next
        pageRoot.bindingMessage = next.length === 0
            ? "All custom bindings removed · defaults apply after reload"
            : "Binding removed"
        pageRoot.saveBindings(next)
    }

    function saveBindings(list) {
        saveBindingsProc.command = [pageRoot.translationHelper, "set-bindings",
            "--translation-binding", pageRoot.translationBinding].concat(list)
        saveBindingsProc.running = true
    }

    function openExternal(cmd) {
        pageRoot.settingsRoot.dismiss()
        Quickshell.execDetached(cmd)
    }

    function startAddKey() {
        if (pageRoot.capturingKey)
            return
        pageRoot.capturingKey = true
        pageRoot.bindingMessage = "Capture window open — press the key, then close it"
        captureKeyProc.running = true
    }

    function finishAddKey(raw) {
        pageRoot.capturingKey = false
        const key = (raw || "").trim()
        if (key.length === 0 || key.startsWith("✓") || key.startsWith("✗") || key.startsWith("ERROR")) {
            pageRoot.bindingMessage = "No key captured"
            bindingMessageTimer.restart()
            return
        }
        // Normalize a few common aliases Hyprland rejects.
        let bind = key
        if (bind === "TOOLS")
            bind = "XF86Tools"
        if (pageRoot.voiceBindings.indexOf(bind) >= 0) {
            pageRoot.bindingMessage = `Already bound: ${pageRoot.friendlyBinding(bind)}`
            bindingMessageTimer.restart()
            return
        }
        const next = pageRoot.voiceBindings.concat([bind])
        pageRoot.voiceBindings = next
        pageRoot.bindingMessage = `Added ${pageRoot.friendlyBinding(bind)}`
        pageRoot.saveBindings(next)
        bindingMessageTimer.restart()
    }

    function refreshTranslationSettings() {
        if (!translationStatusProc.running)
            translationStatusProc.running = true
    }

    function applyTranslationStatus(text) {
        try {
            const result = JSON.parse(text.trim())
            pageRoot.translationModel = result.model || ""
            pageRoot.translationTargetLanguage = result.targetLanguage || "English"
            pageRoot.translationBinding = result.translationBinding || "HANGUL"
            pageRoot.translationHasApiKey = result.hasApiKey === true
            pageRoot.translationReady = result.ready === true
            pageRoot.translationModels = result.models || []
            pageRoot.openCodeConfigPath = result.openCodeConfigPath || ""
            VoiceInput.refreshTranslationConfig()
        } catch (error) {
            pageRoot.translationMessage = "Unable to read translation configuration"
        }
    }

    GridLayout {
        id: contentGrid
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: pageRoot.wideLayout ? 2 : 1
        columnSpacing: SettingsTokens.columnGap
        rowSpacing: SettingsTokens.columnGap

        // ════════════════════════════════════════
        // LEFT · Live / Status
        // ════════════════════════════════════════
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: pageRoot.wideLayout
                ? (contentGrid.width - SettingsTokens.columnGap) / 2
                : contentGrid.width
            implicitHeight: leftColumn.implicitHeight + SettingsTokens.panelPadding * 2
            radius: SettingsTokens.roundRadius
            color: SettingsTokens.panel
            border.width: 1
            border.color: SettingsTokens.line

            ColumnLayout {
                id: leftColumn
                anchors.fill: parent
                anchors.margins: SettingsTokens.panelPadding
                spacing: SettingsTokens.sectionGap

                // Hero header
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
                                text: pageRoot.healthIcon
                                iconSize: 25
                                color: pageRoot.healthWarning ? SettingsTokens.danger : SettingsTokens.accent
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            StyledText {
                                Layout.fillWidth: true
                                text: "Voice input"
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
                                elide: Text.ElideRight
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

                // Trial record
                SettingsSection {
                    title: "Trial record"

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        text: pageRoot.needsSetup
                            ? "Install the engine first, then try a short phrase here."
                            : "Record a short phrase to verify mic, model, and paste."
                        color: SettingsTokens.dim
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.WordWrap
                    }

                    ButtonRow {
                        SettingsButton {
                            label: pageRoot.needsSetup
                                ? "Setup"
                                : pageRoot.isRecording
                                    ? "Stop"
                                    : pageRoot.isTranscribing
                                        ? "Transcribing…"
                                        : "Record"
                            iconName: pageRoot.needsSetup
                                ? "download"
                                : pageRoot.isRecording
                                    ? "stop"
                                    : "mic"
                            active: pageRoot.isRecording
                            enabledState: pageRoot.needsSetup
                                || VoiceInput.state === "idle"
                                || VoiceInput.state === "recording"
                                || VoiceInput.state === "success"
                                || VoiceInput.state === "error"
                            onClicked: {
                                if (pageRoot.needsSetup)
                                    VoiceInput.setup()
                                else
                                    VoiceInput.toggle()
                            }
                        }
                        SettingsButton {
                            label: "Recheck"
                            iconName: "refresh"
                            enabledState: !pageRoot.isRecording && !pageRoot.isTranscribing
                            onClicked: VoiceInput.checkState()
                        }
                    }

                    // Last result panel
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        implicitHeight: resultColumn.implicitHeight + 20
                        radius: SettingsTokens.radius
                        color: SettingsTokens.panelAlt
                        border.width: 1
                        border.color: SettingsTokens.line

                        ColumnLayout {
                            id: resultColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    text: "Last result"
                                    color: SettingsTokens.muted
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                }

                                Item { Layout.fillWidth: true }

                                StyledText {
                                    visible: pageRoot.isRecording
                                    text: `${VoiceInput.recordingDuration.toFixed(1)}s`
                                    color: SettingsTokens.accent
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: VoiceInput.lastTranscription.length > 0
                                    ? VoiceInput.lastTranscription
                                    : pageRoot.isRecording
                                        ? "Listening…"
                                        : pageRoot.isTranscribing
                                            ? "Working…"
                                            : "Nothing yet — try a short phrase."
                                color: VoiceInput.lastTranscription.length > 0
                                    ? SettingsTokens.fg
                                    : SettingsTokens.dim
                                font.pixelSize: Appearance.font.pixelSize.small
                                wrapMode: Text.WordWrap
                            }

                            StyledText {
                                visible: VoiceInput.lastError.length > 0
                                Layout.fillWidth: true
                                text: VoiceInput.lastError
                                color: SettingsTokens.danger
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // Recent history
                SettingsSection {
                    title: "Recent"

                    StyledText {
                        visible: VoiceInput.history.length === 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: "Successful transcriptions will show up here."
                        color: SettingsTokens.dim
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    Repeater {
                        model: VoiceInput.history.slice(0, 5)
                        delegate: SettingsRow {
                            required property var modelData
                            iconName: "history"
                            label: modelData.text ? modelData.text.slice(0, 90) : "--"
                            value: modelData.time || ""
                            clickable: false
                        }
                    }

                    SettingsButton {
                        visible: VoiceInput.history.length > 0
                        Layout.fillWidth: true
                        label: "Clear history"
                        iconName: "clear_all"
                        onClicked: VoiceInput.clearHistory()
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ════════════════════════════════════════
        // RIGHT · Configure
        // ════════════════════════════════════════
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: pageRoot.wideLayout
                ? (contentGrid.width - SettingsTokens.columnGap) / 2
                : contentGrid.width
            implicitHeight: rightColumn.implicitHeight + SettingsTokens.panelPadding * 2
            radius: SettingsTokens.roundRadius
            color: SettingsTokens.panel
            border.width: 1
            border.color: SettingsTokens.line

            ColumnLayout {
                id: rightColumn
                anchors.fill: parent
                anchors.margins: SettingsTokens.panelPadding
                spacing: SettingsTokens.sectionGap

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 40

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 3

                        StyledText {
                            Layout.fillWidth: true
                            text: "Configuration"
                            color: SettingsTokens.fg
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: pageRoot.voiceBindings.length > 0
                                ? `${pageRoot.voiceBindings.length} active trigger${pageRoot.voiceBindings.length === 1 ? "" : "s"}`
                                : "Using default triggers"
                            color: SettingsTokens.muted
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: SettingsTokens.line
                }

                // Keybindings
                SettingsSection {
                    title: "Keybindings"

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        text: "Press a trigger to start or stop recording. Esc cancels only while recording."
                        color: SettingsTokens.dim
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: pageRoot.voiceBindings
                        delegate: Rectangle {
                            id: bindRow
                            required property int index
                            required property var modelData
                            readonly property string raw: modelData
                            readonly property bool isPrimary: index === 0

                            Layout.fillWidth: true
                            implicitHeight: 52
                            radius: SettingsTokens.radius
                            color: bindMouse.containsMouse ? SettingsTokens.cardHover : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 12

                                MaterialSymbol {
                                    Layout.preferredWidth: 22
                                    text: "keyboard"
                                    iconSize: 18
                                    color: SettingsTokens.muted
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: pageRoot.friendlyBinding(bindRow.raw)
                                        color: SettingsTokens.fg
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: bindRow.isPrimary ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: bindRow.isPrimary
                                            ? `Primary · ${bindRow.raw}`
                                            : bindRow.raw
                                        color: SettingsTokens.dim
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        elide: Text.ElideRight
                                    }
                                }

                                SettingsIconButton {
                                    iconName: "close"
                                    onClicked: pageRoot.removeBinding(bindRow.raw)
                                }
                            }

                            MouseArea {
                                id: bindMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }
                    }

                    SettingsRow {
                        visible: pageRoot.voiceBindings.length === 0
                        iconName: "keyboard"
                        label: "Alt + A"
                        description: "Primary default · also Globe (Fn) on supported laptops"
                        clickable: false
                    }

                    SettingsRow {
                        iconName: "info"
                        label: "Esc while recording"
                        description: "Cancels the current take · not a global binding"
                        clickable: false
                    }

                    StyledText {
                        visible: pageRoot.bindingMessage.length > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: pageRoot.bindingMessage
                        color: SettingsTokens.accent
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    ButtonRow {
                        SettingsButton {
                            label: pageRoot.capturingKey ? "Capturing…" : "Add key"
                            iconName: "add"
                            enabledState: !pageRoot.capturingKey
                            active: pageRoot.capturingKey
                            onClicked: pageRoot.startAddKey()
                        }
                        SettingsButton {
                            label: "Edit in TUI"
                            iconName: "open_in_new"
                            onClicked: pageRoot.openExternal(["sumika-launch-settings-voice-tui"])
                        }
                    }
                }

                // Model & engine
                SettingsSection {
                    title: "Voice translation · HANGUL"

                    SettingsRow {
                        iconName: "translate"
                        label: "Translated voice input"
                        description: "Speak Chinese locally, translate online, then paste into the focused app"
                        value: pageRoot.translationReady ? "ready" : "setup"
                        valueColor: pageRoot.translationReady
                            ? SettingsTokens.accent
                            : SettingsTokens.warning
                        clickable: false
                    }

                    SettingsRow {
                        iconName: "model_training"
                        label: "OpenCode model"
                        description: pageRoot.translationModels.length > 0
                            ? "Select from the Voice Model Manager TUI"
                            : "No compatible models found in opencode.json"
                        value: pageRoot.translationModel.length > 0
                            ? pageRoot.translationModel
                            : "unavailable"
                        valueColor: pageRoot.translationModels.length > 0
                            ? SettingsTokens.accent
                            : SettingsTokens.warning
                        onClicked: pageRoot.openExternal(["sumika-launch-settings-voice-tui"])
                    }

                    SettingsRow {
                        iconName: "description"
                        label: "Voice configuration"
                        description: pageRoot.bindingsPath
                        value: `${pageRoot.translationBinding} → ${pageRoot.translationTargetLanguage}`
                        valueColor: SettingsTokens.fg
                        onClicked: pageRoot.openExternal(["sumika-edit-voice-config"])
                    }

                    StyledText {
                        visible: pageRoot.translationMessage.length > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: pageRoot.translationMessage
                        color: pageRoot.translationReady
                            ? SettingsTokens.accent
                            : SettingsTokens.warning
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.WordWrap
                    }

                    ButtonRow {
                        SettingsButton {
                            label: "Model Manager (TUI)"
                            iconName: "open_in_new"
                            onClicked: pageRoot.openExternal(["sumika-launch-settings-voice-tui"])
                        }
                        SettingsButton {
                            label: "Reload OpenCode"
                            iconName: "refresh"
                            enabledState: !translationStatusProc.running
                            onClicked: pageRoot.refreshTranslationSettings()
                        }
                    }
                }

                // Model & engine
                SettingsSection {
                    title: "Model & engine"

                    SettingsRow {
                        iconName: "memory"
                        label: VoiceInput.modelSizeMB > 0
                            ? `SenseVoice · ${VoiceInput.modelSizeMB} MB`
                            : "No model installed"
                        description: VoiceInput.daemonRunning
                            ? "Daemon is warm and ready"
                            : pageRoot.needsSetup
                                ? "Setup creates the venv and downloads the model"
                                : "Daemon starts automatically on first use"
                        value: VoiceInput.daemonRunning ? "up" : "idle"
                        valueColor: VoiceInput.daemonRunning ? SettingsTokens.accent : SettingsTokens.muted
                        clickable: false
                    }

                    ButtonRow {
                        SettingsButton {
                            label: pageRoot.needsSetup ? "Run setup" : "Recheck status"
                            iconName: pageRoot.needsSetup ? "download" : "refresh"
                            onClicked: {
                                if (pageRoot.needsSetup)
                                    VoiceInput.setup()
                                else
                                    VoiceInput.checkState()
                            }
                        }
                        SettingsButton {
                            label: "Full diagnose"
                            iconName: "open_in_new"
                            onClicked: pageRoot.openExternal(["sumika-launch-settings-voice-tui"])
                        }
                    }
                }

                // Advanced
                SettingsDisclosure {
                    title: "Advanced · paths & tools"

                    SettingsRow {
                        label: "Cache"
                        description: VoiceInput.cacheDir
                        clickable: false
                    }
                    SettingsRow {
                        label: "Model"
                        description: VoiceInput.modelDir
                        clickable: false
                    }
                    SettingsRow {
                        label: "Venv"
                        description: VoiceInput.venvDir
                        clickable: false
                    }
                    SettingsRow {
                        label: "Socket"
                        description: "/tmp/sumika-voice.sock"
                        clickable: false
                    }
                    SettingsRow {
                        label: "Bindings file"
                        description: pageRoot.bindingsPath
                        clickable: false
                    }

                    ButtonRow {
                        SettingsButton {
                            label: "TUI test"
                            iconName: "open_in_new"
                            onClicked: pageRoot.openExternal(["sumika-launch-settings-voice-tui"])
                        }
                        SettingsButton {
                            label: "Diagnose"
                            iconName: "open_in_new"
                            onClicked: pageRoot.openExternal(["sumika-launch-settings-voice-tui"])
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

    Process {
        id: voiceBindingsProc
        command: [pageRoot.translationHelper, "bindings"]
        running: true
        stdout: StdioCollector {
            id: voiceBindingsCollector
            onStreamFinished: {
                const text = voiceBindingsCollector.text.trim()
                pageRoot.voiceBindings = text.length > 0
                    ? text.split("\n").filter(l => {
                        const t = l.trim()
                        return t.length > 0 && !t.startsWith("#")
                    }).map(l => l.trim())
                    : []
            }
        }
    }

    Process {
        id: saveBindingsProc
        running: false
        onExited: (exitCode) => {
            pageRoot.refreshBindings()
            Quickshell.execDetached(["hyprctl", "reload"])
            if (exitCode !== 0)
                pageRoot.bindingMessage = "Failed to save bindings"
            bindingMessageTimer.restart()
        }
    }

    // Capture stays over Settings; on close we read state/clipboard and append.
    Process {
        id: captureKeyProc
        command: [pageRoot.keyCaptureTool, "--hotkey"]
        running: false
        onExited: {
            readCaptureProc.running = true
        }
    }

    Process {
        id: readCaptureProc
        command: [
            "python3", "-c",
            "import json, os, subprocess\n" +
            "raw = ''\n" +
            "state_home = os.environ.get('SUMIKA_SHELL_STATE_HOME') or os.path.join(os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')), 'sumika-shell')\n" +
            "state = os.path.join(state_home, 'key-capture.json')\n" +
            "try:\n" +
            "    with open(state, encoding='utf-8') as f:\n" +
            "        data = json.load(f)\n" +
            "    raw = (data.get('raw') or '').strip()\n" +
            "except Exception:\n" +
            "    pass\n" +
            "if not raw:\n" +
            "    try:\n" +
            "        text = subprocess.run(['wl-paste'], capture_output=True, text=True).stdout or ''\n" +
            "        for line in text.splitlines():\n" +
            "            line = line.strip()\n" +
            "            if not line or line.startswith('#') or line.startswith('✓') or line.startswith('✗'):\n" +
            "                continue\n" +
            "            if line.lower().startswith('bind:') or line.lower().startswith('hypr'):\n" +
            "                raw = line.split(':', 1)[-1].strip()\n" +
            "            else:\n" +
            "                raw = line\n" +
            "            break\n" +
            "    except Exception:\n" +
            "        pass\n" +
            "print(raw)\n"
        ]
        running: false
        stdout: StdioCollector {
            id: readCaptureCollector
            onStreamFinished: pageRoot.finishAddKey(readCaptureCollector.text)
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                pageRoot.capturingKey = false
                pageRoot.bindingMessage = "Capture failed"
                bindingMessageTimer.restart()
            }
        }
    }

    Timer {
        id: bindingMessageTimer
        interval: 3500
        repeat: false
        onTriggered: pageRoot.bindingMessage = ""
    }

    Process {
        id: translationStatusProc
        command: [pageRoot.translationHelper, "status"]
        stdout: StdioCollector {
            onStreamFinished: pageRoot.applyTranslationStatus(text)
        }
    }

    Timer {
        id: translationMessageTimer
        interval: 4000
        repeat: false
        onTriggered: pageRoot.translationMessage = ""
    }

    Component.onCompleted: {
        pageRoot.refreshBindings()
        pageRoot.refreshTranslationSettings()
    }
}
