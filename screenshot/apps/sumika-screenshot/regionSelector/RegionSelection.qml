pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    visible: false
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    // During an active recording, let the recorded application keep keyboard
    // focus. Selection/edit modes still need exclusive keyboard input.
    WlrLayershell.keyboardFocus: root.visible && !root.recordingSession
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // Modes
    // TODO: Ask: sidebar AI
    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound } 
    enum SelectionMode { RectCorners, Circle }
    enum Phase { Select, Post }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    property var phase: RegionSelection.Phase.Select
    property bool captureReady: false
    signal dismiss()

    // A zero-area item makes the overlay visually present but click-through
    // during countdown, when there is no recording control to interact with.
    Item { id: noRecordingInput; width: 0; height: 0 }

    // Styles
    property string screenshotDir: Directories.screenshotTemp
    property color overlayColor: ColorUtils.transparentize("#000000", 0.5)
    // Keep screenshot selection neutral. Theme accent colors can be bright
    // green; using them here makes the capture mask visually distracting.
    property color brightText: "#f4f4f4"
    property color brightSecondary: "#b8b8b8"
    property color brightTertiary: "#8f8f8f"
    property color selectionBorderColor: "#e5e5e5"
    property color selectionFillColor: "#22ffffff"
    property color windowBorderColor: brightSecondary
    property color windowFillColor: "#18ffffff"
    property color imageBorderColor: brightTertiary
    property color imageFillColor: "#14ffffff"
    property color onBorderColor: "#ff000000"
    property real targetRegionOpacity: Config.options.regionSelector.targetRegions.opacity
    property bool contentRegionOpacity: Config.options.regionSelector.targetRegions.contentRegionOpacity

    // Vars for indicators
    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => {
        // Sort floating=true windows before others
        if (a.floating === b.floating) return 0;
        return a.floating ? -1 : 1;
    })
    readonly property var layers: HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.5

    // Screen & interaction vars
    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: hyprlandMonitor?.scale ?? 1
    readonly property real monitorOffsetX: hyprlandMonitor?.x ?? 0
    readonly property real monitorOffsetY: hyprlandMonitor?.y ?? 0
    property int activeWorkspaceId: hyprlandMonitor?.activeWorkspace?.id ?? 0
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}-${Date.now()}.png`
    // True when screenshotPath points to a pre-captured file (created by the
    // shell script). We must not delete it on destruction since other monitor
    // instances may still reference it.
    property bool preCapSnapshot: false
    // When true, freeze the bar (hide live menus/popups) after the overlay
    // becomes visible. Overlay first, then freeze — so menus vanish under the
    // already-shown frozen snapshot + mask instead of flashing off a bright
    // empty desktop. Set by SUMIKA_SCREENSHOT_DEFER_FREEZE / pre-cap path.
    property bool closeMenusOnShow: false
    property bool snapshotReady: false
    property string savedScreenshotPath: ""
    property string tempScreenshotPath: ""
    property bool postCaptureReady: false
    // Post-phase tool: "move" repositions/resizes the crop; "mosaic" redacts
    // by pixelating drag-selected rectangles on the frozen snapshot.
    property string postTool: "move"
    // Once the user redacts (mosaic) the frozen image, crop geometry is locked:
    // move/resize handles go away so it is obvious the export region is fixed.
    property bool postGeometryLocked: false
    // Bumped after mosaic so the Image reloads the rewritten snapshot file.
    property int snapshotRevision: 0
    property real mosaicStartX: 0
    property real mosaicStartY: 0
    property real mosaicEndX: 0
    property real mosaicEndY: 0
    property bool mosaicDragging: false
    readonly property real mosaicX: Math.min(mosaicStartX, mosaicEndX)
    readonly property real mosaicY: Math.min(mosaicStartY, mosaicEndY)
    readonly property real mosaicW: Math.abs(mosaicEndX - mosaicStartX)
    readonly property real mosaicH: Math.abs(mosaicEndY - mosaicStartY)
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property real dragDiffX: 0
    property real dragDiffY: 0
    property bool draggedAway: (dragDiffX !== 0 || dragDiffY !== 0)
    property bool dragging: false
    property list<point> points: []
    property var mouseButton: null
    property var imageRegions: []
    readonly property list<var> windowRegions: {
        if (!root.hyprlandMonitor) return [];
        return RegionFunctions.filterWindowRegionsByLayers(
            root.windows.filter(w => w.workspace?.id === root.activeWorkspaceId),
            root.layerRegions
        ).map(window => {
            return {
                at: [window.at[0] - root.monitorOffsetX, window.at[1] - root.monitorOffsetY],
                size: [window.size[0], window.size[1]],
                class: window.class,
                title: window.title,
            }
        });
    }
    readonly property list<var> layerRegions: {
        if (!root.hyprlandMonitor) return [];
        const layersOfThisMonitor = root.layers[root.hyprlandMonitor.name]
        const topLayers = layersOfThisMonitor?.levels["2"]
        if (!topLayers) return [];
        const nonBarTopLayers = topLayers
            .filter(layer => !(layer.namespace.includes(":bar") || layer.namespace.includes(":verticalBar") || layer.namespace.includes(":dock")))
            .map(layer => {
            return {
                at: [layer.x, layer.y],
                size: [layer.w, layer.h],
                namespace: layer.namespace,
            }
        })
        const offsetAdjustedLayers = nonBarTopLayers.map(layer => {
            return {
                at: [layer.at[0] - root.monitorOffsetX, layer.at[1] - root.monitorOffsetY],
                size: layer.size,
                namespace: layer.namespace,
            }
        });
        return offsetAdjustedLayers;
    }

    // Config
    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    // Window click-to-select must stay enabled; content regions need OpenCV which we removed.
    property bool enableWindowRegions: Config.options.regionSelector.targetRegions.windows && !isCircleSelection
    property bool enableLayerRegions: Config.options.regionSelector.targetRegions.layers && !isCircleSelection
    property bool enableContentRegions: false

    function scaledSnapshotCoord(value) {
        return value * root.monitorScale;
    }

    // Target
    property real targetedRegionX: -1
    property real targetedRegionY: -1
    property real targetedRegionWidth: 0
    property real targetedRegionHeight: 0
    function targetedRegionValid() {
        return (root.targetedRegionX >= 0 && root.targetedRegionY >= 0)
    }
    function setRegionToTargeted() {
        const padding = Config.options.regionSelector.targetRegions.selectionPadding; // Make borders not cut off n stuff
        root.regionX = root.targetedRegionX - padding;
        root.regionY = root.targetedRegionY - padding;
        root.regionWidth = root.targetedRegionWidth + padding * 2;
        root.regionHeight = root.targetedRegionHeight + padding * 2;
    }

    function updateTargetedRegion(x, y) {
        // Image regions
        const clickedRegion = root.imageRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedRegion) {
            root.targetedRegionX = clickedRegion.at[0];
            root.targetedRegionY = clickedRegion.at[1];
            root.targetedRegionWidth = clickedRegion.size[0];
            root.targetedRegionHeight = clickedRegion.size[1];
            return;
        }

        // Layer regions
        const clickedLayer = root.layerRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedLayer) {
            root.targetedRegionX = clickedLayer.at[0];
            root.targetedRegionY = clickedLayer.at[1];
            root.targetedRegionWidth = clickedLayer.size[0];
            root.targetedRegionHeight = clickedLayer.size[1];
            return;
        }

        // Window regions
        const clickedWindow = root.windowRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedWindow) {
            root.targetedRegionX = clickedWindow.at[0];
            root.targetedRegionY = clickedWindow.at[1];
            root.targetedRegionWidth = clickedWindow.size[0];
            root.targetedRegionHeight = clickedWindow.size[1];
            return;
        }

        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
    }

    property bool shiftPressed: false

    property real regionWidth: {
        const dx = draggingX - dragStartX;
        const dy = draggingY - dragStartY;
        if (shiftPressed) {
            return Math.max(Math.abs(dx), Math.abs(dy));
        }
        return Math.abs(dx);
    }
    property real regionHeight: {
        const dx = draggingX - dragStartX;
        const dy = draggingY - dragStartY;
        if (shiftPressed) {
            return Math.max(Math.abs(dx), Math.abs(dy));
        }
        return Math.abs(dy);
    }
    property real regionX: {
        const dx = draggingX - dragStartX;
        if (shiftPressed) {
            const size = regionWidth;
            return dx >= 0 ? dragStartX : dragStartX - size;
        }
        return Math.min(dragStartX, draggingX);
    }
    property real regionY: {
        const dy = draggingY - dragStartY;
        if (shiftPressed) {
            const size = regionHeight;
            return dy >= 0 ? dragStartY : dragStartY - size;
        }
        return Math.min(dragStartY, draggingY);
    }

    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    property bool recordWithSound: root.action === RegionSelection.SnipAction.RecordWithSound
    // 0 = idle; 3/2/1 = countdown; recordingActive after backend starts.
    property int recordCountdown: 0
    // Starts as soon as the selection is confirmed and ends after an explicit
    // stop finishes (or a startup failure). Unlike the countdown/backend
    // flags, it has no hand-off gap between countdown and process startup.
    property bool recordingSession: false
    property bool recordingActive: false
    property int recordingElapsedSec: 0
    property string recordingOutputPath: ""
    // True after the recorder stops, while the save/open chrome is shown.
    property bool recordingStopped: false
    // One uninterrupted visual state after the user finishes drawing: the
    // same outside-selection dim is present through countdown, startup, and
    // recording.
    readonly property bool recordingMaskVisible: root.recordingSession
    readonly property string recordingElapsedText: {
        const m = Math.floor(root.recordingElapsedSec / 60);
        const s = root.recordingElapsedSec % 60;
        return `${m}:${s.toString().padStart(2, "0")}`;
    }
    readonly property bool recordingUi: root.isRecording
        && (root.recordingSession || root.recordingStopped)

    Process {
        id: checkRecordingProc
        running: isRecording
        command: ["bash", "-c",
            "pidfile=\"${XDG_RUNTIME_DIR:-/tmp}/sumika-record.pid\"; " +
            "if [ -f \"$pidfile\" ] && kill -0 \"$(cat \"$pidfile\")\" 2>/dev/null; then exit 0; fi; " +
            "exit 1"
        ]
        onExited: (exitCode, exitStatus) => {
            // A second launcher invocation must never act as a stop toggle.
            // Stopping is deliberately reserved for the visible Stop control.
            if (exitCode === 0) {
                root.dismiss();
                return;
            }
            root.preparationDone = true;
        }
    }
    property bool preparationDone: false
    Component.onCompleted: {
        if (!isRecording) {
            preparationDone = true;
        }
    }
    Component.onDestruction: {
        // Only delete the snapshot if we created it ourselves (snapshotProc).
        // Pre-captured snapshots (preCapSnapshot=true) were created by the
        // shell script and should not be removed here.
        if (!root.preCapSnapshot && root.screenshotPath !== "") {
            Quickshell.execDetached(["rm", "-f", root.screenshotPath]);
        }
        // The recorder itself watches this selector process when it was started
        // with --stop-with-parent. Do not stop it here: component destruction
        // can also be caused by unrelated UI/layer changes.
    }
    onPreparationDoneChanged: {
        if (!preparationDone) return;
        if (root.isRecording) {
            // Live compositor capture — show the same darken mask as screenshot
            // select, without a frozen snapshot.
            root.closeMenusOnShow = true;
            root.visible = true;
            root.captureReady = true;
            root.scheduleFreezeAfterOverlay();
        } else {
            // Try to use a pre-captured snapshot from the shell script.
            // The shell exports SUMIKA_SNAPSHOT_PATH_<MONITOR_ENV> where monitor
            // name dashes/dots become underscores (e.g. HDMI-A-1 → HDMI_A_1).
            const snapshotDir = Quickshell.env("SUMIKA_SNAPSHOT_DIR") ?? "";
            const monitorName = root.screen?.name ?? "";
            const monEnv = monitorName.replace(/[-\.]/g, "_");
            const preCapPath = Quickshell.env(`SUMIKA_SNAPSHOT_PATH_${monEnv}`) ?? "";
            // Prefer deferred freeze so the overlay is painted before menus go.
            root.closeMenusOnShow = (Quickshell.env("SUMIKA_SCREENSHOT_DEFER_FREEZE") === "1")
                || preCapPath !== "";
            if (preCapPath !== "") {
                // Pre-captured snapshot exists — use it directly.
                root.screenshotPath = preCapPath;
                root.preCapSnapshot = true;
                root.snapshotReady = true;
                showSnapshotTimer.restart();
            } else {
                // No pre-captured snapshot; fall back to capturing now.
                snapshotProc.running = true;
            }
        }
    }

    // Freeze bar menus only after our Overlay surface is up. IPC is fire-and-
    // forget; by the next frame the live popup is gone under our mask.
    function freezeBarMenus() {
        const barApp = `${Directories.root}/apps/sumika-bar`;
        const qsBin = Quickshell.env("SUMIKA_QS_BIN") || "qs";
        Quickshell.execDetached([
            qsBin, "-p", barApp,
            "ipc", "call", "action", "call", "screenshot.freeze", ""
        ]);
    }

    function scheduleFreezeAfterOverlay() {
        if (!root.closeMenusOnShow)
            return;
        root.closeMenusOnShow = false;
        // Defer one event-loop turn so the layer surface can commit first.
        Qt.callLater(() => root.freezeBarMenus());
    }

    Timer {
        id: showSnapshotTimer
        interval: 16
        repeat: false
        onTriggered: {
            root.visible = true;
            root.captureReady = true;
            // Freeze AFTER the overlay is visible so live menus never flash
            // away on an empty bright frame before the snapshot appears.
            root.scheduleFreezeAfterOverlay();
        }
    }

    Process {
        id: snapshotProc
        running: false
        command: ["bash", "-c",
            `mkdir -p ${ScreenshotAction.quote(root.screenshotDir)} && ` +
            ScreenshotAction.grimHideCursorPrelude() +
            `grim -o ${ScreenshotAction.quote(root.screen.name)} ${ScreenshotAction.quote(root.screenshotPath)}; _grim_ec=$?; ` +
            ScreenshotAction.grimRestoreCursorEpilogue() +
            `exit "$_grim_ec"`
        ]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.snapshotReady = true;
                // Defer menus close until AFTER the overlay becomes visible
                // (handled in showSnapshotTimer.onTriggered).
                root.closeMenusOnShow = true;
                showSnapshotTimer.restart();
            } else {
                console.warn(`[Region Selector] Snapshot capture failed with exit code ${exitCode}.`);
                root.dismiss();
            }
        }
    }

    function getScreenshotAction() {
        switch(root.action) {
            case RegionSelection.SnipAction.Copy:
                return ScreenshotAction.Action.Copy;
            case RegionSelection.SnipAction.Edit:
                return ScreenshotAction.Action.Edit;
            case RegionSelection.SnipAction.Search:
                return ScreenshotAction.Action.Search;
            case RegionSelection.SnipAction.CharRecognition:
                return ScreenshotAction.Action.CharRecognition;
            case RegionSelection.SnipAction.Record:
                return ScreenshotAction.Action.Record;
            case RegionSelection.SnipAction.RecordWithSound:
                return ScreenshotAction.Action.RecordWithSound;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                root.dismiss();
                return;
        }
    }

    Timer {
        id: snipDelayTimer
        interval: 100
        repeat: false
        onTriggered: {
            const saveDir = Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : "";
            var screenshotAction = root.getScreenshotAction();

            if (root.isRecording) {
                // Keep the overlay up: countdown → start backend → stop bar.
                root.phase = RegionSelection.Phase.Post;
                root.selectionMode = RegionSelection.SelectionMode.RectCorners;
                root.postGeometryLocked = true;
                root.postTool = "move";
                root.visible = true;
                root.beginRecordCountdown();
                return;
            }

            if (root.action === RegionSelection.SnipAction.Edit) {
                root.tempScreenshotPath = `/tmp/sumika-screenshot-${Date.now()}.png`;
                root.postCaptureReady = false;
                postCaptureProc.command = ScreenshotAction.getSnapshotCropCommand(
                    root.scaledSnapshotCoord(root.regionX),
                    root.scaledSnapshotCoord(root.regionY),
                    root.scaledSnapshotCoord(root.regionWidth),
                    root.scaledSnapshotCoord(root.regionHeight),
                    root.screenshotPath,
                    root.tempScreenshotPath
                );
                postCaptureProc.running = true;
                root.phase = RegionSelection.Phase.Post;
                root.visible = true;
                return;
            }

            const command = ScreenshotAction.getCommand(
                root.scaledSnapshotCoord(root.regionX),
                root.scaledSnapshotCoord(root.regionY),
                root.scaledSnapshotCoord(root.regionWidth),
                root.scaledSnapshotCoord(root.regionHeight),
                root.screenshotPath,
                screenshotAction,
                saveDir
            );
            Quickshell.execDetached(command);
            root.dismiss();
        }
    }

    Timer {
        id: recordCountdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.recordCountdown > 1) {
                root.recordCountdown -= 1;
                return;
            }
            stop();
            root.recordCountdown = 0;
            root.startScreenRecording();
        }
    }

    Timer {
        id: recordElapsedTimer
        interval: 1000
        repeat: true
        onTriggered: root.recordingElapsedSec += 1
    }

    Process {
        id: recordStartProc
        running: false
        command: []
        stdout: StdioCollector {
            id: recordStartStdout
            waitForEnd: true
            onStreamFinished: {
                const path = (text || "").trim().split("\n").filter(l => l.length > 0).pop() || "";
                if (path !== "")
                    root.recordingOutputPath = path;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn(`[Region Selector] Record start failed (${exitCode}).`);
                root.recordingSession = false;
                root.recordingActive = false;
                root.dismiss();
                return;
            }
            root.recordingActive = true;
            root.recordingElapsedSec = 0;
            recordElapsedTimer.start();
        }
    }

    Process {
        id: recordStopProc
        running: false
        command: ["sumika-record", "--stop"]
        stdout: StdioCollector {
            id: recordStopStdout
            waitForEnd: true
            onStreamFinished: {
                const path = (text || "").trim().split("\n").filter(l => l.length > 0).pop() || "";
                if (path !== "")
                    root.recordingOutputPath = path;
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.recordingSession = false;
            root.recordingActive = false;
            root.recordingStopped = true;
            recordElapsedTimer.stop();
            // Do NOT dismiss: the recordingChrome shows save/open buttons
            // so the user can confirm where the file landed.
        }
    }

    function beginRecordCountdown() {
        // Set this before changing any per-phase state so the visual mask
        // cannot disappear during countdown → process-start hand-off.
        root.recordingSession = true;
        root.recordCountdown = 3;
        root.recordingActive = false;
        root.recordingStopped = false;
        root.recordingElapsedSec = 0;
        root.recordingOutputPath = "";
        recordCountdownTimer.restart();
    }

    function startScreenRecording() {
        // Geometry in global compositor logical coords for wf-recorder -g.
        const gx = Math.round(root.regionX + root.monitorOffsetX);
        const gy = Math.round(root.regionY + root.monitorOffsetY);
        const gw = Math.round(root.regionWidth);
        const gh = Math.round(root.regionHeight);
        const geom = `${gx},${gy} ${gw}x${gh}`;
        const args = ["sumika-record", "--region", geom, "--quiet", "--stop-with-parent"];
        if (root.recordWithSound)
            args.push("--sound");
        recordStartProc.command = args;
        recordStartProc.running = true;
    }

    function stopScreenRecording() {
        recordCountdownTimer.stop();
        root.recordCountdown = 0;
        // Cancel during countdown: nothing to stop yet, just close.
        if (!root.recordingActive && !recordStartProc.running) {
            root.dismiss();
            return;
        }
        recordElapsedTimer.stop();
        // Stop the recorder but keep the overlay up: recordStopProc.onExited
        // flips recordingStopped=true so the chrome shows the save/open/
        // discard controls. The script waits for the MP4 trailer, then
        // prints the final output path to stdout (captured below).
        recordStopProc.running = true;
    }

    Process {
        id: postCaptureProc
        running: false
        command: []
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.postCaptureReady = true;
            } else {
                console.warn(`[Region Selector] Post-capture failed with exit code ${exitCode}.`);
                root.dismiss();
            }
        }
    }

    // Execution after selection
    function snip() {
        if (!root.snapshotReady && !root.isRecording) {
            console.warn("[Region Selector] Snapshot is not ready, skipping snip.");
            return;
        }

        // Validity check
        if (root.regionWidth <= 0 || root.regionHeight <= 0) {
            console.warn("[Region Selector] Invalid region size, skipping snip.");
            root.dismiss();
            return;
        }

        // Clamp region to screen bounds
        root.regionX = Math.max(0, Math.min(root.regionX, root.screen.width - root.regionWidth));
        root.regionY = Math.max(0, Math.min(root.regionY, root.screen.height - root.regionHeight));
        root.regionWidth = Math.max(0, Math.min(root.regionWidth, root.screen.width - root.regionX));
        root.regionHeight = Math.max(0, Math.min(root.regionHeight, root.screen.height - root.regionY));

        // Adjust action
        if (root.action === RegionSelection.SnipAction.Copy) {
            root.action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit : RegionSelection.SnipAction.Copy;
        }

        // Recording keeps the overlay for countdown + chrome (must not cover
        // the recorded region once capture starts — see recording chrome mask).
        snipDelayTimer.start();
    }

    // Re-crop the frozen snapshot to the current region (used after the user
    // moves or resizes the selection box in the Post phase). Keeps
    // tempScreenshotPath in sync with regionX/Y/W/H so copy/save/search/ocr/edit
    // act on the new area.
    function recropPostCapture() {
        root.postCaptureReady = false;
        postCaptureProc.command = ScreenshotAction.getSnapshotCropCommand(
            root.scaledSnapshotCoord(root.regionX),
            root.scaledSnapshotCoord(root.regionY),
            root.scaledSnapshotCoord(root.regionWidth),
            root.scaledSnapshotCoord(root.regionHeight),
            root.screenshotPath,
            root.tempScreenshotPath
        );
        postCaptureProc.running = true;
    }

    // Clamp post-phase geometry into the screen and enforce a minimum size.
    readonly property real postMinSize: 24

    function clampPostGeometry(x, y, w, h) {
        const sw = root.screen?.width ?? root.width;
        const sh = root.screen?.height ?? root.height;
        let width = Math.max(root.postMinSize, w);
        let height = Math.max(root.postMinSize, h);
        width = Math.min(width, sw);
        height = Math.min(height, sh);
        let nx = Math.max(0, Math.min(x, sw - width));
        let ny = Math.max(0, Math.min(y, sh - height));
        // If we hit a wall while resizing, shrink so we stay on-screen.
        if (nx + width > sw)
            width = Math.max(root.postMinSize, sw - nx);
        if (ny + height > sh)
            height = Math.max(root.postMinSize, sh - ny);
        return { x: nx, y: ny, w: width, h: height };
    }

    function applyPostGeometry(x, y, w, h) {
        const g = root.clampPostGeometry(x, y, w, h);
        root.regionX = g.x;
        root.regionY = g.y;
        root.regionWidth = g.w;
        root.regionHeight = g.h;
    }

    function applyMosaicAt(x, y, w, h) {
        if (w < 4 || h < 4 || root.screenshotPath === "")
            return;
        root.postCaptureReady = false;
        mosaicProc.command = ScreenshotAction.getMosaicCommand(
            root.scaledSnapshotCoord(x),
            root.scaledSnapshotCoord(y),
            root.scaledSnapshotCoord(w),
            root.scaledSnapshotCoord(h),
            root.screenshotPath
        );
        mosaicProc.running = true;
    }

    Process {
        id: mosaicProc
        running: false
        command: []
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn(`[Region Selector] Mosaic failed with exit code ${exitCode}.`);
                root.postCaptureReady = true;
                return;
            }
            // Force Image to re-read the rewritten snapshot file.
            root.snapshotRevision += 1;
            // Geometry can no longer change — handles hide after first edit.
            root.postGeometryLocked = true;
            if (root.postTool === "move")
                root.postTool = "mosaic";
            // Re-crop the export temp from the redacted snapshot.
            if (root.tempScreenshotPath !== "")
                root.recropPostCapture();
            else
                root.postCaptureReady = true;
        }
    }

    // corner: "nw" | "ne" | "sw" | "se"
    // mouseX/Y are in actionBarMask / screen coordinates.
    // start* is the geometry when the resize began; aspect is width/height then.
    // shift locks the aspect ratio while keeping the opposite corner fixed.
    function resizePostFromCorner(corner, mouseX, mouseY, startX, startY, startW, startH, aspect, shift) {
        const fixedRight = startX + startW;
        const fixedBottom = startY + startH;
        let left = startX;
        let top = startY;
        let right = fixedRight;
        let bottom = fixedBottom;

        switch (corner) {
        case "nw":
            left = mouseX;
            top = mouseY;
            break;
        case "ne":
            right = mouseX;
            top = mouseY;
            break;
        case "sw":
            left = mouseX;
            bottom = mouseY;
            break;
        case "se":
            right = mouseX;
            bottom = mouseY;
            break;
        }

        let x = Math.min(left, right);
        let y = Math.min(top, bottom);
        let w = Math.max(root.postMinSize, Math.abs(right - left));
        let h = Math.max(root.postMinSize, Math.abs(bottom - top));

        if (shift && aspect > 0.0001) {
            // Dominant axis chooses which side drives the proportional size.
            const rawW = Math.abs(right - left);
            const rawH = Math.abs(bottom - top);
            if (rawW / aspect >= rawH) {
                w = Math.max(root.postMinSize, rawW);
                h = Math.max(root.postMinSize, w / aspect);
            } else {
                h = Math.max(root.postMinSize, rawH);
                w = Math.max(root.postMinSize, h * aspect);
            }
            // Keep the opposite corner fixed.
            switch (corner) {
            case "se":
                x = startX;
                y = startY;
                break;
            case "sw":
                x = fixedRight - w;
                y = startY;
                break;
            case "ne":
                x = startX;
                y = fixedBottom - h;
                break;
            case "nw":
                x = fixedRight - w;
                y = fixedBottom - h;
                break;
            }
        }

        root.applyPostGeometry(x, y, w, h);
    }

    // Input region: full selector while choosing; while recording, only the
    // explicit Stop button receives input and the captured app stays usable.
    mask: Region {
        item: {
            if (root.phase === RegionSelection.Phase.Select)
                return mouseArea;
            if (root.recordingActive)
                return stopRecMouse;
            if (root.recordingStopped)
                return stoppedControls;
            if (root.recordingSession)
                return noRecordingInput;
            return actionBarMask;
        }
    }

    Image {
        id: frozenSnapshot
        anchors.fill: parent
        cache: false
        fillMode: Image.Stretch
        // snapshotRevision cache-busts after in-place mosaic rewrites.
        source: root.snapshotReady
            ? Qt.resolvedUrl(`file://${root.screenshotPath}?r=${root.snapshotRevision}`)
            : ""
        // Live recording has no frozen snapshot underlay.
        visible: root.visible && !root.isRecording && root.snapshotReady
    }

    Item {
        anchors.fill: parent
        visible: root.visible
        focus: root.visible
        Keys.onPressed: (event) => { // Esc closes selection, never an active recording
            if (event.key === Qt.Key_Escape) {
                if (root.recordingUi) {
                    // Recording is intentionally stopped only by its visible
                    // Stop button. Ignore Escape and other incidental input.
                    event.accepted = true;
                    return;
                }
                root.dismiss();
            } else if (event.key === Qt.Key_Shift) {
                root.shiftPressed = true;
            }
        }
        Keys.onReleased: (event) => {
            if (event.key === Qt.Key_Shift) {
                root.shiftPressed = false;
            }
        }
    }

    // Frozen screenshot/edit selection has its own mask layer, separate from
    // the selection MouseArea. This keeps the dimming stable even when input
    // routing changes for the recording workflow.
    readonly property bool screenshotMaskVisible: root.visible
        && !root.isRecording
        && root.captureReady
        && root.selectionMode === RegionSelection.SelectionMode.RectCorners
    Rectangle {
        visible: root.screenshotMaskVisible
        x: 0; y: 0; width: parent.width
        height: Math.max(0, root.regionY)
        color: root.overlayColor
    }
    Rectangle {
        visible: root.screenshotMaskVisible
        x: 0
        y: Math.min(parent.height, root.regionY + root.regionHeight)
        width: parent.width
        height: Math.max(0, parent.height - y)
        color: root.overlayColor
    }
    Rectangle {
        visible: root.screenshotMaskVisible
        x: 0
        y: Math.max(0, root.regionY)
        width: Math.max(0, root.regionX)
        height: Math.max(0, Math.min(parent.height, root.regionY + root.regionHeight) - y)
        color: root.overlayColor
    }
    Rectangle {
        visible: root.screenshotMaskVisible
        x: Math.min(parent.width, root.regionX + root.regionWidth)
        y: Math.max(0, root.regionY)
        width: Math.max(0, parent.width - x)
        height: Math.max(0, Math.min(parent.height, root.regionY + root.regionHeight) - y)
        color: root.overlayColor
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: root.phase === RegionSelection.Phase.Select ? Qt.BlankCursor : Qt.ArrowCursor
        acceptedButtons: root.phase === RegionSelection.Phase.Select ? Qt.LeftButton | Qt.RightButton : Qt.NoButton
        hoverEnabled: root.phase === RegionSelection.Phase.Select

        // Controls
        onPressed: (mouse) => {
            if (!root.snapshotReady && !root.isRecording) {
                mouse.accepted = true;
                return;
            }
            root.shiftPressed = (mouse.modifiers & Qt.ShiftModifier) !== 0;
            root.dragStartX = mouse.x;
            root.dragStartY = mouse.y;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragging = true;
            root.mouseButton = mouse.button;
        }
        onReleased: (mouse) => {
            if (!root.dragging) {
                mouse.accepted = true;
                return;
            }
            root.shiftPressed = (mouse.modifiers & Qt.ShiftModifier) !== 0;
            // Detect if it was a click -> Try to select targeted region
            if (root.draggingX === root.dragStartX && root.draggingY === root.dragStartY) {
                if (root.targetedRegionValid()) {
                    root.setRegionToTargeted();
                } else {
                    // Empty click (no window target): keep overlay open instead of
                    // treating it as a zero-size capture that immediately dismisses.
                    root.dragging = false;
                    return;
                }
            }
            // Circle dragging?
            else if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                const padding = Config.options.regionSelector.circle.padding + Config.options.regionSelector.circle.strokeWidth / 2;
                const dragPoints = (root.points.length > 0) ? root.points : [{ x: mouseArea.mouseX, y: mouseArea.mouseY }];
                const maxX = Math.max(...dragPoints.map(p => p.x));
                const minX = Math.min(...dragPoints.map(p => p.x));
                const maxY = Math.max(...dragPoints.map(p => p.y));
                const minY = Math.min(...dragPoints.map(p => p.y));
                root.regionX = minX - padding;
                root.regionY = minY - padding;
                root.regionWidth = maxX - minX + padding * 2;
                root.regionHeight = maxY - minY + padding * 2;
            }
            root.snip();
        }
        onPositionChanged: (mouse) => {
            root.shiftPressed = (mouse.modifiers & Qt.ShiftModifier) !== 0;
            if (!root.dragging) {
                root.updateTargetedRegion(mouse.x, mouse.y);
                return;
            }
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragDiffX = mouse.x - root.dragStartX;
            root.dragDiffY = mouse.y - root.dragStartY;
            if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                root.points.push({ x: mouse.x, y: mouse.y });
            }
        }
        
        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
            sourceComponent: RectCornersSelectionDetails {
                regionX: root.regionX
                regionY: root.regionY
                regionWidth: root.regionWidth
                regionHeight: root.regionHeight
                mouseX: root.dragging
                    ? (root.draggingX >= root.dragStartX ? root.regionX + root.regionWidth : root.regionX)
                    : mouseArea.mouseX
                mouseY: root.dragging
                    ? (root.draggingY >= root.dragStartY ? root.regionY + root.regionHeight : root.regionY)
                    : mouseArea.mouseY
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                // RectCornersSelectionDetails keeps its outside mask visible
                // in this mode; hide only its dashed selection decorations
                // because recordingChrome supplies the red recording frame.
                breathingBorderOnly: root.recordingActive
                showOutsideOverlay: root.isRecording
                captureReady: root.captureReady && root.phase === RegionSelection.Phase.Select
            }
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.Circle
            sourceComponent: CircleSelectionDetails {
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                points: root.points
            }
        }

        CursorGuide {
            z: 9999
            visible: root.phase === RegionSelection.Phase.Select && root.dragging
            x: root.regionX + root.regionWidth - width / 2
            y: root.regionY + root.regionHeight - height / 2
            action: root.action
            selectionMode: root.selectionMode
        }

        // Window regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableWindowRegions) {
                        return root.windowRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 2
                required property var modelData
                clientDimensions: modelData
                showIcon: true
                targeted: !root.draggedAway && //
                    (root.targetedRegionX === modelData.at[0]  //
                    && root.targetedRegionY === modelData.at[1] //
                    && root.targetedRegionWidth === modelData.size[0] //
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.class}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Layer regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableLayerRegions) {
                        return root.layerRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 3
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.namespace}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Content regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableContentRegions) {
                        return root.imageRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 4
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.contentRegionOpacity
                borderColor: root.imageBorderColor
                fillColor: targeted ? root.imageFillColor : "transparent"
                text: "Content region"
            }
        }


    }

    // Post-phase full-screen capture + action bar
    Item {
        id: actionBarMask
        visible: root.phase === RegionSelection.Phase.Post && !root.isRecording
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                // Esc exits mosaic only while geometry is still editable.
                if (root.postTool === "mosaic" && !root.postGeometryLocked) {
                    root.postTool = "move";
                    root.mosaicDragging = false;
                    event.accepted = true;
                    return;
                }
                root.dismiss();
            }
        }

        // Full-screen mouse capture: click outside buttons = dismiss
        // (disabled while drawing mosaic regions).
        MouseArea {
            anchors.fill: parent
            z: 0
            enabled: root.postTool !== "mosaic"
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onClicked: root.dismiss()
        }

        // Mosaic draw layer — only mapped while the mosaic tool is armed so it
        // cannot steal hover/cursor from the resize handles in move mode.
        MouseArea {
            id: mosaicDrawArea
            anchors.fill: parent
            z: 12
            visible: root.postTool === "mosaic"
            enabled: root.postTool === "mosaic" && root.postCaptureReady
            hoverEnabled: true
            cursorShape: Qt.CrossCursor
            acceptedButtons: Qt.LeftButton

            onPressed: (mouse) => {
                root.mosaicDragging = true;
                root.mosaicStartX = mouse.x;
                root.mosaicStartY = mouse.y;
                root.mosaicEndX = mouse.x;
                root.mosaicEndY = mouse.y;
            }
            onPositionChanged: (mouse) => {
                if (!root.mosaicDragging)
                    return;
                root.mosaicEndX = Math.max(0, Math.min(mouse.x, width));
                root.mosaicEndY = Math.max(0, Math.min(mouse.y, height));
            }
            onReleased: (mouse) => {
                if (!root.mosaicDragging)
                    return;
                root.mosaicDragging = false;
                root.mosaicEndX = Math.max(0, Math.min(mouse.x, width));
                root.mosaicEndY = Math.max(0, Math.min(mouse.y, height));
                if (root.mosaicW >= 4 && root.mosaicH >= 4)
                    root.applyMosaicAt(root.mosaicX, root.mosaicY, root.mosaicW, root.mosaicH);
            }
            onCanceled: root.mosaicDragging = false
        }

        // Live preview of the mosaic region being drawn.
        Rectangle {
            visible: root.postTool === "mosaic" && root.mosaicDragging && root.mosaicW > 0 && root.mosaicH > 0
            x: root.mosaicX
            y: root.mosaicY
            width: root.mosaicW
            height: root.mosaicH
            z: 13
            color: "#33ffcc00"
            border.color: "#ffcc00"
            border.width: 2
            radius: 2
        }

        // Post-phase selection frame: drag the body to move; drag a corner
        // handle to resize. Hold Shift while resizing to lock aspect ratio
        // (opposite corner stays fixed). Geometry updates live so the bright
        // crop hole and action bar follow; recrop runs on release.
        // z above the dismiss catcher so corner HoverHandlers can set cursors.

        Rectangle {
            id: postSelectionBox
            visible: root.phase === RegionSelection.Phase.Post && !root.isRecording && root.regionWidth > 0 && root.regionHeight > 0
            x: root.regionX
            y: root.regionY
            width: root.regionWidth
            height: root.regionHeight
            color: "transparent"
            border.color: root.selectionBorderColor
            border.width: 2
            radius: 4
            z: 10
            opacity: root.postTool === "mosaic" ? 0.55 : 1

            readonly property real handleSize: 14
            readonly property real handleHitPad: 10
            readonly property bool geometryEditable: root.postTool === "move" && !root.postGeometryLocked

            // Move body (handles sit on top and take corner events).
            // Hidden interaction once the image has been edited (mosaic).
            MouseArea {
                id: postDragArea
                anchors.fill: parent
                anchors.margins: postSelectionBox.handleSize / 2
                enabled: postSelectionBox.geometryEditable
                hoverEnabled: true
                cursorShape: Qt.SizeAllCursor
                property real grabOffsetX: 0
                property real grabOffsetY: 0

                onPressed: (mouse) => {
                    root.postCaptureReady = false;
                    const p = mapToItem(actionBarMask, mouse.x, mouse.y);
                    grabOffsetX = p.x - root.regionX;
                    grabOffsetY = p.y - root.regionY;
                }
                onPositionChanged: (mouse) => {
                    if (!pressed)
                        return;
                    const sw = root.screen?.width ?? root.width;
                    const sh = root.screen?.height ?? root.height;
                    const p = mapToItem(actionBarMask, mouse.x, mouse.y);
                    const nx = Math.max(0, Math.min(p.x - grabOffsetX, sw - root.regionWidth));
                    const ny = Math.max(0, Math.min(p.y - grabOffsetY, sh - root.regionHeight));
                    root.regionX = nx;
                    root.regionY = ny;
                }
                onReleased: root.recropPostCapture()
            }

            component CornerHandle: Item {
                id: handle
                required property string corner
                required property int handleCursor

                // Larger hit target than the visual knob so diagonal cursors
                // engage before the move-area margins steal the hover.
                width: postSelectionBox.handleSize + postSelectionBox.handleHitPad * 2
                height: postSelectionBox.handleSize + postSelectionBox.handleHitPad * 2
                z: 20
                // Drop the knobs after the first redaction so the crop looks fixed.
                visible: !root.postGeometryLocked

                x: {
                    switch (handle.corner) {
                    case "nw": case "sw": return -width / 2;
                    case "ne": case "se": return parent.width - width / 2;
                    default: return 0;
                    }
                }
                y: {
                    switch (handle.corner) {
                    case "nw": case "ne": return -height / 2;
                    case "sw": case "se": return parent.height - height / 2;
                    default: return 0;
                    }
                }

                // Visual knob (centered in the hit target).
                Rectangle {
                    anchors.centerIn: parent
                    width: postSelectionBox.handleSize
                    height: postSelectionBox.handleSize
                    radius: 2
                    color: root.selectionBorderColor
                    border.width: 1
                    border.color: "#cc000000"
                }

                // HoverHandler is more reliable than MouseArea alone for
                // cursorShape on wlroots layer-shell surfaces.
                HoverHandler {
                    enabled: postSelectionBox.geometryEditable
                    cursorShape: handle.handleCursor
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: postSelectionBox.geometryEditable
                    hoverEnabled: true
                    cursorShape: handle.handleCursor
                    preventStealing: true
                    // Keep the body-drag MouseArea from winning the grab.
                    propagateComposedEvents: false

                    property real startX: 0
                    property real startY: 0
                    property real startW: 0
                    property real startH: 0
                    property real startAspect: 1

                    onPressed: (mouse) => {
                        root.postCaptureReady = false;
                        startX = root.regionX;
                        startY = root.regionY;
                        startW = root.regionWidth;
                        startH = root.regionHeight;
                        startAspect = startH > 0 ? startW / startH : 1;
                        mouse.accepted = true;
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed)
                            return;
                        const p = mapToItem(actionBarMask, mouse.x, mouse.y);
                        const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                        root.resizePostFromCorner(
                            handle.corner, p.x, p.y,
                            startX, startY, startW, startH,
                            startAspect, shift
                        );
                    }
                    onReleased: root.recropPostCapture()
                }
            }

            CornerHandle {
                corner: "nw"
                handleCursor: Qt.SizeFDiagCursor
            }
            CornerHandle {
                corner: "ne"
                handleCursor: Qt.SizeBDiagCursor
            }
            CornerHandle {
                corner: "sw"
                handleCursor: Qt.SizeBDiagCursor
            }
            CornerHandle {
                corner: "se"
                handleCursor: Qt.SizeFDiagCursor
            }
        }

        // Action bar (on top, buttons intercept clicks)
        Item {
            z: 20
            x: {
                const rightEdge = root.regionX + root.regionWidth;
                const barW = width;
                const clampedX = Math.max(0, rightEdge - barW);
                return Math.min(clampedX, root.width - barW);
            }
            y: {
                const barH = height;
                const yBelow = root.regionY + root.regionHeight + 12;
                if (yBelow + barH > root.height)
                    return Math.max(0, root.regionY - 12 - barH);
                return yBelow;
            }
            width: actionBar.implicitWidth
            height: actionBar.implicitHeight

            Row {
                id: actionBar
                spacing: 8
                // Stay clickable while mosaic tool is armed even if a recrop is
                // in flight for the other buttons; individual handlers check ready.
                opacity: root.postCaptureReady || root.postTool === "mosaic" ? 1 : 0.45

                Rectangle {
                    id: mosaicButton
                    width: 40; height: 40; radius: 8
                    color: mosaicMouse.containsMouse || root.postTool === "mosaic"
                        ? TuiStyle.controlHover : TuiStyle.control
                    border.width: 1
                    border.color: root.postTool === "mosaic"
                        ? TuiStyle.controlActiveBorder
                        : (mosaicMouse.containsMouse ? TuiStyle.controlActiveBorder : TuiStyle.menuBorder)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        color: root.postTool === "mosaic" || mosaicMouse.containsMouse
                            ? TuiStyle.accent : TuiStyle.fg
                        text: "grid_on"
                    }

                    MouseArea {
                        id: mosaicMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // After any redaction the crop is locked — stay in
                            // mosaic mode so the user can only add more redaction
                            // or export, not re-open move/resize.
                            if (root.postGeometryLocked) {
                                root.postTool = "mosaic";
                                root.mosaicDragging = false;
                                return;
                            }
                            if (root.postTool === "mosaic") {
                                root.postTool = "move";
                                root.mosaicDragging = false;
                            } else {
                                root.postTool = "mosaic";
                                root.mosaicDragging = false;
                            }
                        }
                    }
                }

                Rectangle {
                    id: copyButton
                    width: 40; height: 40; radius: 8
                    enabled: root.postCaptureReady
                    opacity: enabled ? 1 : 0.45
                    color: copyMouse.containsMouse ? TuiStyle.controlHover : TuiStyle.control
                    border.width: 1
                    border.color: copyMouse.containsMouse ? TuiStyle.controlActiveBorder : TuiStyle.menuBorder

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        color: copyMouse.containsMouse ? TuiStyle.accent : TuiStyle.fg
                        text: "content_copy"
                    }

                    MouseArea {
                        id: copyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(ScreenshotAction.getTempFileCommand(
                                root.tempScreenshotPath,
                                ScreenshotAction.Action.Copy,
                                ""
                            ));
                            root.dismiss();
                        }
                    }
                }

                Rectangle {
                    id: saveButton
                    width: 40; height: 40; radius: 8
                    color: saveMouse.containsMouse ? TuiStyle.controlHover : TuiStyle.control
                    border.width: 1
                    border.color: saveMouse.containsMouse ? TuiStyle.controlActiveBorder : TuiStyle.menuBorder

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        color: saveMouse.containsMouse ? TuiStyle.accent : TuiStyle.fg
                        text: "save"
                    }

                    MouseArea {
                        id: saveMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const saveDir = Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : "";
                            Quickshell.execDetached(ScreenshotAction.getTempFileCommand(
                                root.tempScreenshotPath,
                                ScreenshotAction.Action.Copy,
                                saveDir
                            ));
                            root.dismiss();
                        }
                    }
                }

                Rectangle {
                    id: searchButton
                    width: 40; height: 40; radius: 8
                    color: searchMouse.containsMouse ? TuiStyle.controlHover : TuiStyle.control
                    border.width: 1
                    border.color: searchMouse.containsMouse ? TuiStyle.controlActiveBorder : TuiStyle.menuBorder

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        color: searchMouse.containsMouse ? TuiStyle.accent : TuiStyle.fg
                        text: "image_search"
                    }

                    MouseArea {
                        id: searchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(ScreenshotAction.getTempFileCommand(
                                root.tempScreenshotPath,
                                ScreenshotAction.Action.Search
                            ));
                            root.dismiss();
                        }
                    }
                }

                Rectangle {
                    id: ocrButton
                    width: 40; height: 40; radius: 8
                    color: ocrMouse.containsMouse ? TuiStyle.controlHover : TuiStyle.control
                    border.width: 1
                    border.color: ocrMouse.containsMouse ? TuiStyle.controlActiveBorder : TuiStyle.menuBorder

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        color: ocrMouse.containsMouse ? TuiStyle.accent : TuiStyle.fg
                        text: "text_snippet"
                    }

                    MouseArea {
                        id: ocrMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(ScreenshotAction.getTempFileCommand(
                                root.tempScreenshotPath,
                                ScreenshotAction.Action.CharRecognition
                            ));
                            root.dismiss();
                        }
                    }
                }

                Rectangle {
                    id: editButton
                    width: 40; height: 40; radius: 8
                    color: editMouse.containsMouse ? TuiStyle.controlHover : TuiStyle.control
                    border.width: 1
                    border.color: editMouse.containsMouse ? TuiStyle.controlActiveBorder : TuiStyle.menuBorder

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        color: editMouse.containsMouse ? TuiStyle.accent : TuiStyle.fg
                        text: "edit"
                    }

                    MouseArea {
                        id: editMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(ScreenshotAction.getTempFileCommand(
                                root.tempScreenshotPath,
                                ScreenshotAction.Action.Edit
                            ));
                            root.dismiss();
                        }
                    }
                }
            }
        }
    }

    // Recording chrome is visual-only except for its compact control bars, so
    // the recorded application stays interactive. The video never captures a
    // full-screen overlay. Three states share this surface:
    //   1. countdown (recordCountdown 3/2/1) — big number + hint
    //   2. recording (recordingActive) — timer + stop button
    //   3. stopped (recordingStopped) — save / open / discard buttons
    Item {
        id: recordingChrome
        anchors.fill: parent
        visible: root.recordingUi

        // Keep one explicit mask from the first countdown frame through the
        // live recording state. It covers only the four areas outside the
        // capture rectangle, so wf-recorder's -g selection never records it.
        // Keeping it in the chrome avoids a visual gap when input switches
        // away from the selection MouseArea after the box is completed.
        Rectangle {
            visible: root.recordingMaskVisible
            x: 0; y: 0
            width: parent.width
            height: Math.max(0, root.regionY)
            color: root.overlayColor
        }
        Rectangle {
            visible: root.recordingMaskVisible
            x: 0
            y: Math.min(parent.height, root.regionY + root.regionHeight)
            width: parent.width
            height: Math.max(0, parent.height - y)
            color: root.overlayColor
        }
        Rectangle {
            visible: root.recordingMaskVisible
            x: 0
            y: Math.max(0, root.regionY)
            width: Math.max(0, root.regionX)
            height: Math.max(0, Math.min(parent.height, root.regionY + root.regionHeight) - y)
            color: root.overlayColor
        }
        Rectangle {
            visible: root.recordingMaskVisible
            x: Math.min(parent.width, root.regionX + root.regionWidth)
            y: Math.max(0, root.regionY)
            width: Math.max(0, parent.width - x)
            height: Math.max(0, Math.min(parent.height, root.regionY + root.regionHeight) - y)
            color: root.overlayColor
        }

        // ── Countdown overlay (state 1) ──
        Item {
            visible: root.recordCountdown > 0
            anchors.centerIn: parent

            Rectangle {
                anchors.centerIn: parent
                width: 180
                height: 180
                radius: 24
                color: Qt.rgba(0, 0, 0, 0.55)
                border.color: root.selectionBorderColor
                border.width: 2

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.recordCountdown.toString()
                        color: root.brightText
                        font.family: Appearance.font.family.main
                        font.pixelSize: 72
                        font.weight: Font.Black
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Starting recording…"
                        color: root.brightSecondary
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                    }
                }
            }
        }

        // No border is drawn around the capture rectangle: compositor scaling
        // can place a border's pixels inside the captured geometry.
        // ── Recording timer + stop bar (state 2): above the selection ──
        Item {
            id: recordingControls
            visible: root.recordingActive
            x: {
                const rightEdge = root.regionX + root.regionWidth;
                const barW = width;
                const clampedX = Math.max(0, rightEdge - barW);
                return Math.min(clampedX, root.width - barW);
            }
            y: {
                const barH = height;
                const yAbove = root.regionY - 12 - barH;
                const yBelow = root.regionY + root.regionHeight + 12;
                if (yAbove >= 0)
                    return yAbove;
                if (yBelow + barH <= root.height)
                    return yBelow;
                // Both edges overflow (near-fullscreen region): clamp inside.
                return Math.max(0, root.height - barH - 12);
            }
            width: recordBar.implicitWidth
            height: recordBar.implicitHeight

            Row {
                id: recordBar
                spacing: 8

                // Timer pill: pulsing red dot + elapsed time
                Rectangle {
                    width: Math.max(110, recTimerText.implicitWidth + 36)
                    height: 40
                    radius: 8
                    color: Qt.rgba(0, 0, 0, 0.65)
                    border.width: 1
                    border.color: Qt.rgba(0.9, 0.2, 0.2, 0.7)

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12
                            radius: 6
                            color: "#e53935"
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 0.25; duration: 700 }
                                NumberAnimation { from: 0.25; to: 1; duration: 700 }
                            }
                        }

                        StyledText {
                            id: recTimerText
                            text: root.recordingElapsedText
                            color: root.brightText
                            font.family: Appearance.font.family.main
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // Stop button
                Rectangle {
                    width: 40; height: 40; radius: 8
                    color: stopRecMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.9) : Qt.rgba(0, 0, 0, 0.65)
                    border.width: 1
                    border.color: stopRecMouse.containsMouse ? "#e53935" : Qt.rgba(0.9, 0.2, 0.2, 0.7)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        color: root.brightText
                        text: "stop"
                    }

                    MouseArea {
                        id: stopRecMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.stopScreenRecording()
                    }
                }
            }
        }

        // ── Stopped state: save / open / discard (state 3) ──
        // Anchored below the selection (or above if there is no room).
        Item {
            id: stoppedControls
            visible: root.recordingStopped
            x: {
                const rightEdge = root.regionX + root.regionWidth;
                const barW = width;
                const clampedX = Math.max(0, rightEdge - barW);
                return Math.min(clampedX, root.width - barW);
            }
            y: {
                const barH = height;
                const yBelow = root.regionY + root.regionHeight + 12;
                if (yBelow + barH > root.height)
                    return Math.max(0, root.regionY - 12 - barH);
                return yBelow;
            }
            width: stoppedBar.implicitWidth
            height: stoppedBar.implicitHeight

            Row {
                id: stoppedBar
                spacing: 8

                Rectangle {
                    width: 40; height: 40; radius: 8
                    color: saveRecMouse.containsMouse ? TuiStyle.controlHover : Qt.rgba(0, 0, 0, 0.65)
                    border.width: 1
                    border.color: saveRecMouse.containsMouse ? TuiStyle.accent : Qt.rgba(1, 1, 1, 0.2)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        color: saveRecMouse.containsMouse ? TuiStyle.accent : root.brightText
                        text: "save"
                    }

                    MouseArea {
                        id: saveRecMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.recordingOutputPath) {
                                const saveDir = Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : "";
                                Quickshell.execDetached(["bash", "-c",
                                    `cp -f '${root.recordingOutputPath.replace(/'/g, "'\\''")}' '${(saveDir || "${XDG_VIDEOS_DIR:-$HOME/Videos}").replace(/'/g, "'\\''")}' 2>/dev/null || cp -f '${root.recordingOutputPath.replace(/'/g, "'\\''")}' "$HOME/Videos"`]);
                            }
                            root.dismiss();
                        }
                    }
                }

                Rectangle {
                    width: 40; height: 40; radius: 8
                    color: openRecMouse.containsMouse ? TuiStyle.controlHover : Qt.rgba(0, 0, 0, 0.65)
                    border.width: 1
                    border.color: openRecMouse.containsMouse ? TuiStyle.accent : Qt.rgba(1, 1, 1, 0.2)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        color: openRecMouse.containsMouse ? TuiStyle.accent : root.brightText
                        text: "folder_open"
                    }

                    MouseArea {
                        id: openRecMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.recordingOutputPath)
                                Quickshell.execDetached(["xdg-open", root.recordingOutputPath]);
                        }
                    }
                }

                Rectangle {
                    width: 40; height: 40; radius: 8
                    color: discardRecMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.6) : Qt.rgba(0, 0, 0, 0.65)
                    border.width: 1
                    border.color: discardRecMouse.containsMouse ? "#e53935" : Qt.rgba(1, 1, 1, 0.2)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        color: root.brightText
                        text: "delete"
                    }

                    MouseArea {
                        id: discardRecMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.recordingOutputPath)
                                Quickshell.execDetached(["rm", "-f", root.recordingOutputPath]);
                            root.dismiss();
                        }
                    }
                }
            }
        }
    }
}
