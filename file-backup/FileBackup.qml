pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.core.runtime
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string state: "init"
    property string lastError: ""
    property bool hasConnection: false

    readonly property string shareDir: FileUtils.trimFileProtocol(Qt.resolvedUrl(".")) + "/bin"
    readonly property string dataDir: `${FileUtils.trimFileProtocol(Directories.config)}/sumika-shell/file-backup`


    // ── Status polling ──
    Process {
        id: statusProc

        command: ["sh", "-c", `${root.shareDir}/omd-backup status`]

        stdout: StdioCollector {
            onStreamFinished: {
                const output = text.trim();
                if (output.includes('"ok":true') || output.includes("not configured")) {
                    root.hasConnection = true;
                } else {
                    root.hasConnection = false;
                }
                root.state = "ready";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const errText = text.trim();
                if (errText.length > 0) {
                    console.warn("[FileBackup] status error:", errText);
                    root.lastError = errText;
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.lastError.length === 0)
                root.lastError = `Backup status check failed (code ${code})`;
        }
    }

    // ── Public API ──

    function openSettings() {
        // Open the settings page via Quickshell's settings navigation
        Quickshell.execDetached([`${root.shareDir}/omd-launch-settings-backup-tui`]);
    }

    function refreshStatus() {
        root.lastError = "";
        if (!statusProc.running)
            statusProc.running = true;
    }

    function togglePopup() {
        GlobalStates.barPopupType = GlobalStates.barPopupType === "backup" ? "" : "backup";
    }

    Component.onCompleted: {
        console.log("[FileBackup] Component.onCompleted running");
        Quickshell.execDetached(["mkdir", "-p", root.dataDir]);
        root.refreshStatus();
    }
    IpcHandler {
        target: "backup"

        function toggle(): void {
            root.togglePopup();
        }
        function refresh(): void {
            root.refreshStatus();
        }
        function settings(): void {
            root.openSettings();
        }
    }


}
