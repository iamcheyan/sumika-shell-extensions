pragma ComponentBehavior: Bound
pragma Singleton
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell

Singleton {
    id: root
    readonly property string ocrBinary: (function() {
        const mh = Quickshell.env("SUMIKA_MODULES_HOME")
        if (mh) return `${mh}/ocr/bin/sumika-ocr`
        return "sumika-ocr"
    })()
    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound
    }

    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    function quote(value) {
        return `'${StringUtils.shellSingleQuoteEscape(value)}'`;
    }

    // Shared grim pre/post: hide the software cursor via cursor.invisible.
    // Do NOT warp the pointer off-screen — Hyprland clamps that to (0,0) and
    // the arrow ends up in the top-left of every capture.
    function grimHideCursorPrelude() {
        return ` _prev_invis=$(hyprctl getoption cursor:invisible -j 2>/dev/null | jq -r '.bool // false' 2>/dev/null || echo false); ` +
            `if hyprctl monitors -j >/dev/null 2>&1; then ` +
            `hyprctl eval "hl.config({ cursor = { invisible = true } })" >/dev/null 2>&1 || true; ` +
            `elif command -v ydotool >/dev/null 2>&1; then ` +
            `YDOTOOL_SOCKET="\${YDOTOOL_SOCKET:-/tmp/.ydotool_socket}" ydotool key 148 >/dev/null 2>&1 || true; ` +
            `fi; sleep 0.03; `;
    }

    function grimRestoreCursorEpilogue() {
        return ` if hyprctl monitors -j >/dev/null 2>&1; then ` +
            `if [ "\${_prev_invis:-false}" = "true" ]; then ` +
            `hyprctl eval "hl.config({ cursor = { invisible = true } })" >/dev/null 2>&1 || true; ` +
            `else hyprctl eval "hl.config({ cursor = { invisible = false } })" >/dev/null 2>&1 || true; fi; ` +
            `elif command -v ydotool >/dev/null 2>&1; then ` +
            `YDOTOOL_SOCKET="\${YDOTOOL_SOCKET:-/tmp/.ydotool_socket}" ydotool mousemove -x 1 -y 0 >/dev/null 2>&1 || true; ` +
            `fi; `;
    }

    function regionString(x, y, width, height) {
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        return `${rx},${ry} ${rw}x${rh}`;
    }

    function annotationCommand() {
        return `${Config.options.regionSelector.annotation.useSatty ? "satty" : "swappy"} -f -`;
    }

    function uploadCurrentTempCommand() {
        return `curl -sF files[]=@"$tmpFile" ${quote(root.fileUploadApiEndpoint)} | jq -r '.files[0].url'`;
    }

    function tempFilePrefixForAction(action) {
        switch (action) {
            case ScreenshotAction.Action.Search:
                return "sumika-search";
            case ScreenshotAction.Action.CharRecognition:
                return "sumika-ocr";
            default:
                return "sumika-screenshot";
        }
    }

    function getTempCaptureCommand(x, y, width, height, tempPath) {
        const region = regionString(x, y, width, height);
        return ["bash", "-c",
            grimHideCursorPrelude() +
            `grim -g ${quote(region)} ${quote(tempPath)}; ` +
            grimRestoreCursorEpilogue()
        ];
    }

    function getSnapshotCropCommand(x, y, width, height, snapshotPath, tempPath) {
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        return ["bash", "-c",
            `magick ${quote(snapshotPath)} -crop ${rw}x${rh}+${rx}+${ry} +repage ${quote(tempPath)}`
        ];
    }

    // Pixelate (mosaic) a rectangle on the frozen snapshot in-place.
    // Coords are in snapshot pixel space (already scale-adjusted).
    // Uses scale-down + nearest-neighbor scale-up — cheap and very readable
    // as a redaction effect compared to a soft Gaussian blur.
    function getMosaicCommand(x, y, width, height, imagePath) {
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.max(1, Math.round(width));
        const rh = Math.max(1, Math.round(height));
        // ~12px blocks: stronger mosaic on larger regions, still legible cells.
        const block = 12;
        const smallW = Math.max(1, Math.round(rw / block));
        const smallH = Math.max(1, Math.round(rh / block));
        return ["bash", "-c",
            `img=${quote(imagePath)}; ` +
            `tmp=$(mktemp "/tmp/sumika-mosaic.XXXXXX.png"); ` +
            `magick "$img" ` +
            `\\( +clone -crop ${rw}x${rh}+${rx}+${ry} +repage ` +
            `-sample ${smallW}x${smallH}! -sample ${rw}x${rh}! \\) ` +
            `-geometry +${rx}+${ry} -compose over -composite "$tmp" && ` +
            `mv -f "$tmp" "$img"`
        ];
    }

    function getRegionCommand(x, y, width, height, action, saveDir = "") {
        const region = regionString(x, y, width, height);
        const regionArg = quote(region);
        const tempPrefix = tempFilePrefixForAction(action);

        switch (action) {
            case ScreenshotAction.Action.Record:
                return ["bash", "-c", `${quote(Directories.recordScriptPath)} --region ${regionArg}`];
            case ScreenshotAction.Action.RecordWithSound:
                return ["bash", "-c", `${quote(Directories.recordScriptPath)} --region ${regionArg} --sound`];
            default: {
                const command = `tmpFile=$(mktemp /tmp/${tempPrefix}.XXXXXX.png) && ` +
                    `trap 'rm -f "$tmpFile"' EXIT && ` +
                    grimHideCursorPrelude() +
                    `grim -g ${regionArg} "$tmpFile"; _grim_ec=$?; ` +
                    grimRestoreCursorEpilogue() +
                    ` [ "$_grim_ec" -eq 0 ] || exit "$_grim_ec"; ` +
                    tempFileActionScript("$tmpFile", action, saveDir, false);
                return ["bash", "-c", command];
            }
        }
    }

    function tempFileActionScript(tempFileExpression, action, saveDir = "", installCleanupTrap = true) {
        const setup = installCleanupTrap
            ? `tmpFile=${quote(tempFileExpression)}; trap 'rm -f "$tmpFile"' EXIT; `
            : "";

        switch (action) {
            case ScreenshotAction.Action.Copy:
                if (saveDir === "") {
                    return `${setup}cliphist store < "$tmpFile" 2>/dev/null || true; cat "$tmpFile" | wl-copy`;
                }
                return `${setup}saveDir=${quote(saveDir)}; ` +
                    `mkdir -p "$saveDir" && ` +
                    `savePath="$saveDir/screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png" && ` +
                    `cp "$tmpFile" "$savePath" && ` +
                    `cliphist store < "$tmpFile" 2>/dev/null || true; ` +
                    `cat "$tmpFile" | wl-copy`;
            case ScreenshotAction.Action.Edit:
                return `${setup}cat "$tmpFile" | ${annotationCommand()}`;
            case ScreenshotAction.Action.Search:
                return `${setup}xdg-open "${root.imageSearchEngineBaseUrl}$(${uploadCurrentTempCommand()})"`;
            case ScreenshotAction.Action.CharRecognition:
                return `${setup}${root.ocrBinary} "$tmpFile" 2>/dev/null | wl-copy`;
            case ScreenshotAction.Action.Record:
            case ScreenshotAction.Action.RecordWithSound:
                console.warn("[Region Selector] Record actions require a selected region, not a temp file.");
                return `${setup}true`;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                return `${setup}false`;
        }
    }

    function getTempFileCommand(tempPath, action, saveDir = "") {
        return ["bash", "-c", tempFileActionScript(tempPath, action, saveDir, true)];
    }

    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "") {
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        const cropBase = `magick "$screenshotFile" -crop ${rw}x${rh}+${rx}+${ry} +repage`;
        const tempPrefix = tempFilePrefixForAction(action);

        switch (action) {
            case ScreenshotAction.Action.Record:
            case ScreenshotAction.Action.RecordWithSound:
                return getRegionCommand(x, y, width, height, action, saveDir);
            default: {
                const command = `tmpFile=$(mktemp /tmp/${tempPrefix}.XXXXXX.png) && ` +
                    `screenshotFile=${quote(screenshotPath)} && ` +
                    `trap 'rm -f "$tmpFile" "$screenshotFile"' EXIT && ` +
                    `${cropBase} "$tmpFile" && ` +
                    tempFileActionScript("$tmpFile", action, saveDir, false);
                return ["bash", "-c", command];
            }
        }
    }

    function getGrimCommand(x, y, width, height, action, saveDir = "") {
        return getRegionCommand(x, y, width, height, action, saveDir);
    }
}
