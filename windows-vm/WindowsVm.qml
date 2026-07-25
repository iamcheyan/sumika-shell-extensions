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
    property string containerStatus: "missing"
    property string phase: "not-installed"
    property bool ready: false

    readonly property string shareDir: FileUtils.trimFileProtocol(Qt.resolvedUrl(".")) + "/bin"


    // ── Lifecycle ──
    Component.onCompleted: {
        console.log("[WindowsVm] Component.onCompleted running");
        root.refreshStatus();
    }

    // ── Public functions ──
    function openSettings() {
        GlobalStates.barPopupType = "";
        ActionManager.invoke("settings.open", {page: "windows-vm"});
    }

    function togglePopup() {
        GlobalStates.barPopupType = GlobalStates.barPopupType === "windows-vm" ? "" : "windows-vm";
    }

    function refreshStatus() {
        if (!statusProc.running)
            statusProc.running = true;
    }

    // ── Status Process ──
    Process {
        id: statusProc
        command: ["bash", "-c", "omd-settings-windows-vm status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = {};
                    const lines = (text || "").split("\n");
                    for (const line of lines) {
                        const idx = line.indexOf("=");
                        if (idx > 0) {
                            data[line.slice(0, idx)] = line.slice(idx + 1);
                        }
                    }
                    root.containerStatus = data.container || "missing";
                    root.phase = data.phase || "not-installed";
                    root.ready = data.ready === "true";
                    root.state = root.ready ? "ready" : (root.containerStatus === "running" ? "running" : "idle");
                    root.lastError = "";
                } catch (e) {
                    console.error("[WindowsVm] status parse error:", e);
                    root.lastError = String(e);
                }
            }
        }
    }

    // ── IpcHandler ──
    IpcHandler {
        target: "windows-vm"

        function toggle(): void {
            root.togglePopup();
        }
        function settings(): void {
            root.openSettings();
        }
        function refresh(): void {
            root.refreshStatus();
        }
    }
}
