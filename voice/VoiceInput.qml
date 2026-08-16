pragma Singleton
pragma ComponentBehavior: Bound

import qs.core.runtime
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string state: "init"
    property real recordingDuration: 0
    property string lastTranscription: ""
    property string lastError: ""
    property string activeMode: "dictation"
    readonly property real maxRecordingDuration: 90.0

    // ── 历史记录 ──
    property list<var> history: []
    readonly property int maxHistory: 20

    // ── 模型信息 ──
    property int modelSizeMB: 0
    property bool daemonRunning: false
    property bool transcriptionDelivered: false
    property bool translationReady: false
    property bool translationHasApiKey: false
    property string translationEndpoint: ""
    property string translationModel: ""
    property string translationTargetLanguage: "English"
    property bool speculativeTranslationEnabled: true
    property string translationConfigPath: ""
    property string translationSource: ""
    property string translationOutput: ""
    property string translationError: ""
    property string speculativeSource: ""
    property string speculativeOutput: ""
    property var speculativeMetrics: ({})
    property bool awaitingSpeculation: false
    property double recordingStartedAt: 0
    property double recordingStoppedAt: 0
    property double transcriptionStartedAt: 0
    property double translationStartedAt: 0
    property var lastTranslationMetrics: ({})

    readonly property string cacheDir: FileUtils.trimFileProtocol(`${Directories.genericCache}/sumika-voice`)
    readonly property string modelDir: `${root.cacheDir}/sense-voice-small-int8`
    // Per-user runtime dir (0700); never use fixed /tmp paths.
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || `/run/user/${Quickshell.env("UID") || ""}`
    readonly property string wavPath: `${root.runtimeDir}/sumika-voice-rec.wav`
    readonly property string recPidFile: `${root.runtimeDir}/sumika-voice-rec.pid`
    readonly property string cancelFlagFile: `${root.runtimeDir}/sumika-voice-cancel`

    readonly property string shareDir: {
        const dir = FileUtils.trimFileProtocol(Qt.resolvedUrl(".")) + "/bin"
        return dir
    }

    // paste-at-cursor lives in the extension's own bin/ dir
    readonly property string pasteScript: `${root.shareDir}/sumika-paste-at-cursor`
    readonly property string translationHelper: `${root.shareDir}/sumika-voice-translate`
    readonly property string speculationHelper: `${root.shareDir}/sumika-voice-speculate`

    // 录音开始时记录焦点窗口，转写完成后贴回该窗口（避免转写期间焦点跑到顶栏）。
    property string focusedWindowClass: ""
    property string focusedWindowAddress: ""

    function pasteTargetForWindow() {
        return root.focusedWindowAddress
            ? `address:${root.focusedWindowAddress}`
            : "activewindow"
    }

    // 异步刷新录音开始时的焦点窗口 class + address
    Process {
        id: focusClassProc
        command: ["bash", "-c",
            "hyprctl -j activewindow 2>/dev/null | jq -r '[.class // empty, .address // empty] | @tsv' 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split("\t")
                root.focusedWindowClass = parts[0] || ""
                root.focusedWindowAddress = parts[1] || ""
            }
        }
    }

    Component.onCompleted: {
        if (ModuleLoader.isEnabled("voice")) {
            Quickshell.execDetached(["mkdir", "-p", `${root.cacheDir}`])
            root.checkState()
            root.refreshModelInfo()
            root.refreshDaemonStatus()
            root.refreshTranslationConfig()
        } else {
            console.log("[VoiceInput] voice module disabled, skipping init")
        }
    }
    onStateChanged: {
        if (state === "recording") {
            // Bind Escape to cancel via file flag (self-contained, no bar IPC needed)
            Quickshell.execDetached(["hyprctl", "eval", `o.bind("escape", "Cancel voice recording", "touch '${root.cancelFlagFile}'")`])
        } else {
            Quickshell.execDetached(["hyprctl", "eval", "hl.unbind(\"escape\")"])
        }
        if (state === "success") {
            successResetTimer.restart()
        } else if (state === "error") {
            errorResetTimer.restart()
        }
    }

    Timer {
        id: successResetTimer
        interval: 1500
        repeat: false
        running: false
        onTriggered: {
            if (root.state === "success") root.state = "idle"
        }
    }

    Timer {
        id: errorResetTimer
        interval: 2000
        repeat: false
        running: false
        onTriggered: {
            if (root.state === "error") root.state = "idle"
        }
    }

    // ── 录音超时和计时 ──
    Timer {
        id: recordingTimer
        interval: 100
        repeat: true
        running: root.state === "recording"
        onTriggered: {
            root.recordingDuration += 0.1
            // Check for cancel signal from Escape keybinding
            cancelFileCheckProc.running = true
            if (root.recordingDuration >= root.maxRecordingDuration) {
                root.stopRecording()
                root.notify("⚠️ 语音输入超时", `已达到最大录音时间 ${root.maxRecordingDuration} 秒，开始自动转写…`, "dialog-warning")
            }
        }
    }

    // ── 取消信号检测 ──
    Process {
        id: cancelFileCheckProc
        running: false
        command: ["test", "-f", root.cancelFlagFile]
        onExited: (code, status) => {
            if (code === 0) {
                Quickshell.execDetached(["rm", "-f", root.cancelFlagFile])
                root.cancel()
            }
        }
    }
    // ── 模型信息刷新 ──
    function refreshModelInfo() {
        modelInfoProc.running = true
    }

    Process {
        id: modelInfoProc
        command: ["bash", "-c",
            `du -sm '${root.modelDir}' 2>/dev/null | awk '{print $1}' || echo 0`]
        stdout: SplitParser {
            onRead: (line) => {
                root.modelSizeMB = parseInt(line) || 0
            }
        }
    }

    // ── 守护进程状态刷新 ──
    function refreshDaemonStatus() {
        daemonCheckProc.running = true
    }

    Process {
        id: daemonCheckProc
        command: ["bash", "-c",
            `if [ -S '${root.runtimeDir}/sumika-voice.sock' ] && ss -xl src '${root.runtimeDir}/sumika-voice.sock' 2>/dev/null | grep -q LISTEN; then echo running; else echo stopped; fi`]
        stdout: SplitParser {
            onRead: (line) => {
                root.daemonRunning = (line === "running")
            }
        }
    }

    function refreshTranslationConfig() {
        if (!translationStatusProc.running)
            translationStatusProc.running = true
    }

    Process {
        id: translationStatusProc
        command: [root.translationHelper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim())
                    root.translationReady = result.ready === true
                    root.translationHasApiKey = result.hasApiKey === true
                    root.translationEndpoint = result.endpoint || ""
                    root.translationModel = result.model || ""
                    root.translationTargetLanguage = result.targetLanguage || "English"
                    root.speculativeTranslationEnabled = result.speculativeEnabled !== false
                    root.translationConfigPath = result.configPath || ""
                } catch (error) {
                    root.translationReady = false
                    console.warn("[VoiceInput] unable to read translation config:", error)
                }
            }
        }
    }

    // ── 桌面通知 helper ──
    function notify(title, body, icon) {
        var args = ["notify-send", "-a", "Sumika Shell Voice", "-t", "3000"]
        if (icon) args.push("-i", icon)
        args.push(title, body)
        Quickshell.execDetached(args)
    }

    // ── 状态检测 ──
    function checkState() {
        modelCheckProc.running = true
    }

    Process {
        id: modelCheckProc
        command: ["bash", "-c",
            `if [ -f '${root.modelDir}/model.int8.onnx' ] && [ -f '${root.modelDir}/tokens.txt' ]; then echo model-ok; else echo model-missing; fi`]
        stdout: SplitParser {
            onRead: (line) => {
                if (line === "model-ok") {
                    venvCheckProc.running = true
                } else {
                    root.state = "setup"
                }
            }
        }
    }

    Process {
        id: venvCheckProc
        command: ["bash", "-c",
            `if [ -f '${root.venvDir}/bin/python3' ] && '${root.venvDir}/bin/python3' -c 'import sherpa_onnx, numpy' 2>/dev/null; then echo venv-ok; else echo venv-missing; fi`]
        stdout: SplitParser {
            onRead: (line) => {
                if (line === "venv-ok") {
                    root.state = "idle"
                    root.refreshDaemonStatus()
                } else {
                    root.state = "setup"
                }
            }
        }
    }

    // ── 首次设置流程 ──
    function setup() {
        if (root.state !== "setup") return
        root.notify("⬇️ 正在准备语音输入",
            "首次使用需要安装依赖和下载模型，约需30秒…")
        setupProc.running = true
    }

    Process {
        id: setupProc
        command: ["bash", `${root.shareDir}/sumika-voice-setup`]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("ERROR")) {
                    root.lastError = line
                    root.state = "error"
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                if (root.state !== "error") {
                    root.lastError = "依赖安装失败 (code " + code + ")"
                    root.state = "error"
                }
                return
            }
            if (root.state === "setup") {
                root.notify("⬇️ 正在下载模型", "约需30秒…")
                downloadProc.running = true
            }
        }
    }

    Process {
        id: downloadProc
        command: ["bash", `${root.shareDir}/sumika-voice-download`]
        stdout: SplitParser {
            onRead: (line) => {
                if (line === "model-ready") {
                    root.refreshModelInfo()
                    root.notify("✅ 准备完成", "开始录音", "audio-input-microphone")
                    root.state = "idle"
                    root.startRecording()
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.state === "setup") {
                root.lastError = "模型下载失败 (code " + code + ")"
                root.state = "error"
            }
        }
    }

    // ── 主切换逻辑 ──
    function toggle() {
        if (state === "setup") {
            root.setup()
            return
        }
        if (state === "error") {
            root.checkState()
            return
        }
        if (state === "idle") startRecording()
        else if (state === "recording") stopRecording()
    }

    function toggleTranslation() {
        if (state === "setup") {
            root.notify("语音翻译尚未就绪", "请先完成本地语音模型设置", "dialog-warning")
            return
        }
        if (state === "error") {
            root.checkState()
            return
        }
        if (state === "idle") {
            if (!root.translationReady) {
                root.refreshTranslationConfig()
                root.notify(
                    "语音翻译尚未配置",
                    "请在 Voice Model Manager 中选择可用的 OpenCode 模型和目标语言",
                    "dialog-warning"
                )
                return
            }
            root.startRecording("translation")
        } else if (state === "recording") {
            root.stopRecording()
        }
    }

    function startRecording(mode) {
        root.activeMode = mode || "dictation"
        root.testMode = false
        root.transcriptionDelivered = false
        root.recordingDuration = 0
        root.lastTranscription = ""
        root.lastError = ""
        root.speculativeSource = ""
        root.speculativeOutput = ""
        root.speculativeMetrics = ({})
        root.awaitingSpeculation = false
        root.lastTranslationMetrics = ({})
        root.recordingStartedAt = Date.now()
        root.recordingStoppedAt = 0
        // 记录当前焦点窗口 class，转写完成时按此选 paste 命令
        focusClassProc.running = false
        focusClassProc.running = true
        state = "recording"
        recProc.running = true
        if (root.activeMode === "translation" && root.speculativeTranslationEnabled)
            speculationProc.running = true
    }

    function stopRecording() {
        if (state !== "recording") return
        stopRecProc.running = true
    }

    function cancel() {
        if (state !== "recording") return
        speculationProc.running = false
        state = "idle"
        stopRecProc.running = true
    }

    function isMeaningfulText(text) {
        var cleaned = text.replace(/<\|[^|]+\|>/g, "").trim()
        if (cleaned.length === 0) return false
        return !/^[\s\.,!?。，！？、…\-]+$/.test(cleaned)
    }

    Process {
        id: recProc
        command: ["bash", `${root.shareDir}/sumika-voice-record`, "start"]
    }

    Process {
        id: stopRecProc
        command: ["bash", `${root.shareDir}/sumika-voice-record`, "stop"]
        onExited: (code, status) => {
            if (root.state === "recording") {
                state = "transcribing"
                root.recordingStoppedAt = Date.now()
                root.transcriptionStartedAt = Date.now()
                transcribeProc.running = true
            }
        }
    }

    property bool testMode: false

    Process {
        id: transcribeProc
        command: ["bash", "-c",
            `"${root.shareDir}/sumika-voice-transcribe" "${root.wavPath}"`]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var result = JSON.parse(line)
                    if (result.text !== undefined) {
                        if (root.isMeaningfulText(result.text)) {
                            if (root.transcriptionDelivered) {
                                console.warn("[VoiceInput] ignoring duplicate transcription result")
                                return
                            }
                            root.transcriptionDelivered = true
                            root.lastTranscription = result.text
                            if (root.testMode) {
                                root.onTestTranscriptionResult(result.text)
                            } else if (root.activeMode === "translation") {
                                root.handleFinalTranslationSource(result.text)
                            } else {
                                root.onTranscriptionResult(result.text)
                            }
                        } else {
                            root.lastError = "没有检测到语音"
                        }
                    } else if (result.error) {
                        root.lastError = result.error === "no-speech-detected"
                            ? "没有检测到语音（请检查麦克风或说大声一点）"
                            : result.error
                    }
                } catch (e) {
                    console.error("[VoiceInput] parse error:", e)
                    root.lastError = "转写结果解析失败"
                }
            }
        }
        onExited: (code, status) => {
            if (root.state !== "transcribing") return
            if (code !== 0 && root.lastError === "" && root.lastTranscription === "") {
                root.lastError = "转写失败 (code " + code + ")"
            }
            if (root.lastError === "" && root.lastTranscription === "") {
                root.lastError = "没有检测到语音"
            }
            root.state = root.lastError === "" ? "success" : "idle"
            root.testMode = false
        }
    }

    function onTranscriptionResult(text) {
        root.addToHistory(text)
        root.deliverText(text, "voice")
    }

    function deliverText(text, source) {
        const target = root.pasteTargetForWindow()
        console.log("[VoiceInput] deliverText mode=" + root.activeMode + " text='" + text
            + "' class=" + root.focusedWindowClass + " target=" + target)
        Quickshell.execDetached(["bash", "-c",
            `payload=$(mktemp); trap 'rm -f "$payload"' EXIT; ` +
            `printf '%s' '${StringUtils.shellSingleQuoteEscape(text)}' > "$payload" && ` +
            `wl-copy < "$payload" && SUMIKA_PASTE_SOURCE=${source || "voice"} ` +
            `'${root.pasteScript}' --file "$payload" auto '${StringUtils.shellSingleQuoteEscape(root.focusedWindowClass)}' '${StringUtils.shellSingleQuoteEscape(target)}'`])
    }

    Process {
        id: speculationProc
        command: [
            root.speculationHelper,
            root.wavPath,
            "--pid-path", root.recPidFile,
            "--transcribe-helper", `${root.shareDir}/sumika-voice-transcribe`,
            "--translate-helper", root.translationHelper
        ]

        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const result = JSON.parse(line)
                    if (result.event === "source") {
                        root.speculativeSource = result.source || ""
                        root.speculativeOutput = ""
                        root.speculativeMetrics = {
                            audioMs: result.audioMs || 0,
                            transcribeMs: result.transcribeMs || 0,
                            translationStartedAtMs: result.translationStartedAtMs || Date.now()
                        }
                    } else if (result.event === "invalidated") {
                        if (root.speculativeSource === (result.source || "")) {
                            root.speculativeSource = ""
                            root.speculativeOutput = ""
                            root.speculativeMetrics = ({})
                        }
                    } else if (result.event === "result") {
                        root.speculativeSource = result.source || ""
                        root.speculativeOutput = result.text || ""
                        root.speculativeMetrics = {
                            audioMs: result.audioMs || 0,
                            transcribeMs: result.transcribeMs || 0,
                            translateMs: result.translateMs || 0,
                            apiSeconds: result.apiSeconds || 0,
                            translationStartedAtMs: result.translationStartedAtMs
                                || root.speculativeMetrics.translationStartedAtMs
                                || 0,
                            finalTranscribeMs: root.speculativeMetrics.finalTranscribeMs || 0
                        }
                        if (root.awaitingSpeculation
                                && root.translationSource === root.speculativeSource
                                && root.speculativeOutput.length > 0) {
                            root.acceptTranslation(root.speculativeOutput, true)
                        }
                    }
                } catch (error) {
                    console.warn("[VoiceInput] speculative result parse error:", error)
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (root.awaitingSpeculation && !translationProc.running)
                root.awaitingSpeculation = false
        }
    }

    function handleFinalTranslationSource(text) {
        root.translationSource = text
        const transcriptionMs = Math.max(0, Date.now() - root.transcriptionStartedAt)
        if (root.speculativeSource === text && root.speculativeOutput.length > 0) {
            root.speculativeMetrics.finalTranscribeMs = transcriptionMs
            root.acceptTranslation(root.speculativeOutput, true)
            return
        }
        if (root.speculativeSource === text && speculationProc.running) {
            root.speculativeMetrics.finalTranscribeMs = transcriptionMs
            root.startTranslation(text, true)
            return
        }
        speculationProc.running = false
        root.startTranslation(text)
    }

    function startTranslation(text, raceSpeculation) {
        root.awaitingSpeculation = raceSpeculation === true
        root.translationSource = text
        root.translationOutput = ""
        root.translationError = ""
        root.translationStartedAt = Date.now()
        root.state = "translating"
        translationProc.stdinEnabled = true
        translationProc.running = true
    }

    function acceptTranslation(text, speculative) {
        root.awaitingSpeculation = false
        if (!speculative)
            speculationProc.running = false
        root.translationOutput = text
        root.lastTranscription = text
        root.addToHistory(text)
        root.deliverText(text, speculative ? "voice-translation-speculative" : "voice-translation")
        const completedAt = Date.now()
        root.lastTranslationMetrics = {
            mode: speculative ? "speculative" : "normal",
            recordingToPasteMs: Math.max(0, completedAt - root.recordingStartedAt),
            releaseToPasteMs: Math.max(0, completedAt - root.recordingStoppedAt),
            finalTranscribeMs: speculative
                ? (root.speculativeMetrics.finalTranscribeMs || 0)
                : Math.max(0, root.translationStartedAt - root.transcriptionStartedAt),
            translationMs: speculative
                ? (root.speculativeMetrics.translateMs || 0)
                : Math.max(0, completedAt - root.translationStartedAt),
            speculativeAudioMs: speculative
                ? (root.speculativeMetrics.audioMs || 0)
                : 0,
            speculativeTranscribeMs: speculative
                ? (root.speculativeMetrics.transcribeMs || 0)
                : 0,
            speculativeLeadMs: speculative
                ? Math.max(0, root.recordingStoppedAt
                    - (root.speculativeMetrics.translationStartedAtMs || root.recordingStoppedAt))
                : 0
        }
        console.log("[VoiceInput] translation metrics:",
            JSON.stringify(root.lastTranslationMetrics))
        root.state = "success"
        root.activeMode = "dictation"
    }

    Process {
        id: translationProc
        command: [root.translationHelper, "translate"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim())
                    root.translationOutput = result.text || ""
                } catch (error) {
                    root.translationError = "翻译服务返回了无效结果"
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const output = text.trim()
                if (output.length === 0)
                    return
                try {
                    const result = JSON.parse(output)
                    root.translationError = result.error || output
                } catch (error) {
                    root.translationError = output
                }
            }
        }

        onRunningChanged: {
            if (running) {
                write(root.translationSource)
                stdinEnabled = false
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (root.state !== "translating")
                return
            if (exitCode === 0 && root.translationOutput.length > 0) {
                root.acceptTranslation(root.translationOutput, false)
            } else {
                root.lastTranscription = root.translationSource
                root.lastError = root.translationError
                    || `语音翻译失败 (code ${exitCode})`
                Quickshell.execDetached(["wl-copy", root.translationSource])
                root.notify(
                    "语音翻译失败",
                    root.lastError + "；中文识别结果已复制到剪贴板",
                    "dialog-error"
                )
                root.state = "error"
                root.activeMode = "dictation"
            }
        }
    }

    // ── 调试：不自动粘贴，只复制文本并打开设置面板展示结果 ──
    function onTestTranscriptionResult(text) {
        Quickshell.execDetached(["bash", "-c",
            `printf '%s' '${StringUtils.shellSingleQuoteEscape(text)}' | wl-copy`])
        root.lastTranscription = text
        root.addToHistory(text)
        root.openSettings()
    }

    // ── 历史记录 ──
    function addToHistory(text) {
        var now = new Date()
        var timeStr = now.getHours().toString().padStart(2, '0') + ":" + 
                      now.getMinutes().toString().padStart(2, '0')
        var entry = { text: text, time: timeStr }
        var newHistory = [entry].concat(root.history)
        if (newHistory.length > root.maxHistory) {
            newHistory = newHistory.slice(0, root.maxHistory)
        }
        root.history = newHistory
    }

    function clearHistory() {
        root.history = []
    }

    // ── 测试录音（3秒自动停止） ──
    function testRecording() {
        if (root.state !== "idle") {
            return
        }
        root.testMode = true
        root.activeMode = "dictation"
        root.transcriptionDelivered = false
        root.recordingDuration = 0
        root.lastTranscription = ""
        root.lastError = ""
        state = "recording"
        recProc.running = true
        testStopTimer.restart()
    }

    Timer {
        id: testStopTimer
        interval: 3000
        repeat: false
        running: false
        onTriggered: {
            if (root.state === "recording") {
                stopRecProc.running = true
            }
        }
    }

    // ── 打开设置面板 ──
    function openSettings() {
        GlobalStates.barPopupType = "voice"
    }

}
