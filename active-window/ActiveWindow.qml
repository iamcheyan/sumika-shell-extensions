import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland

Item {
    id: root

    property int titleAreaWidth: 280
    property bool hideOnShortScreen: true

    // Content max width: titleAreaWidth minus left/right padding (10+10),
    // the 14px icon, and the 6px spacing. The text elides past this.
    readonly property real maxContentWidth: titleAreaWidth - 20 - 14 - 6

    // Compositor-agnostic focused-window lookup via zwlr_foreign_toplevel_management_v1
    // (labwc 0.20+, Hyprland, sway, …). `activated` is the wlr-ftm focus state;
    // `screens` limits the match to this bar's output on multi-monitor setups.
    // Falls back to the OS name when nothing is focused on this screen.
    readonly property var focusedToplevel: {
        const barScreen = root.screen?.name ?? "";
        const matches = ToplevelManager.toplevels.values.filter(t =>
            t.activated && t.screens.some(s => s.name === barScreen));
        return matches[0] ?? null;
    }

    readonly property bool hasWindowOnWorkspace: root.focusedToplevel !== null
    readonly property string windowTitle: root.focusedToplevel?.title ?? ""
    readonly property string windowIconClass: root.focusedToplevel?.appId ?? ""
    readonly property string displayTitle: root.hasWindowOnWorkspace ? root.windowTitle : root.desktopDisplayName()
    readonly property string osIconPath: Qt.resolvedUrl("icons/" + root.osIconName() + ".svg")

    readonly property var screen: root.QsWindow.window?.screen
    readonly property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0

    /// Toplevel captured at click time — the menu acts on the window the
    /// user clicked on, not whatever becomes active while the menu is open.
    property var menuTarget: null

    // Width follows content (icon + text + padding) so the pill hugs the
    // label like the workspaces/applications buttons, capped at
    // titleAreaWidth so a long window title elides instead of stretching
    // the bar. Computed explicitly from the text's natural width — do NOT
    // read it from contentRow.implicitWidth: contentRow is anchored to
    // parent, creating a circular binding that collapses the width.
    implicitWidth: Math.min(
        (10 + 10) + 14 + 6 + titleText.implicitWidth,
        titleAreaWidth)
    implicitHeight: 28
    visible: !root.hideOnShortScreen || root.useShortenedForm === 0

    function fallbackLetter(appId, title) {
        const source = (appId && appId.length > 0) ? appId : (title ?? "");
        if (!source || source.length === 0)
            return "?";
        return source.charAt(0).toUpperCase();
    }

    function desktopDisplayName() {
        var name = SystemInfo.distroName;
        if (!name || name.length === 0) return "Desktop";
        // Strip trailing parenthesized variants: "Fedora Linux Asahi Remix 44 (KDE Plasma Desktop Edition)" → "Fedora Linux Asahi Remix 44"
        name = name.replace(/\s*\([^)]*\)\s*$/, "").trim();
        // Append version if not already in name
        var ver = SystemInfo.distroVersion;
        if (ver && ver.length > 0 && !name.includes(ver)) {
            name += " " + ver;
        }
        return name || "Desktop";
    }

    function osIconName() {
        const id = (SystemInfo.distroId || "").toLowerCase();
        const like = (SystemInfo.distroLike || "").toLowerCase();
        const name = (SystemInfo.distroName || "").toLowerCase();

        // Tier 1: exact distroId match
        const idMap = {
            "fedora": "fedora",
            "arch": "arch",
            "artix": "arch",
            "cachyos": "arch",
            "ubuntu": "ubuntu",
            "debian": "debian",
            "raspbian": "debian",
            "kali": "debian",
            "linuxmint": "mint",
            "endeavouros": "endeavouros",
            "nixos": "nixos",
            "manjaro": "manjaro",
            "opensuse": "opensuse",
            "suse": "opensuse",
            "popos": "pop-os",
            "zorin": "zorin-os",
            "centos": "centos",
            "redhat": "redhat",
            "rocky": "rockylinux",
            "alpine": "alpine",
            "gentoo": "gentoo",
            "funtoo": "gentoo",
        };
        if (id in idMap) return idMap[id];

        // Tier 2: check ID_LIKE (can be space-separated, e.g. "fedora rhel")
        const likeMap = {
            "fedora": "fedora",
            "arch": "arch",
            "debian": "debian",
            "ubuntu": "ubuntu",
            "rhel": "redhat",
            "centos": "centos",
            "alpine": "alpine",
            "gentoo": "gentoo",
        };
        const likes = like.split(/\s+/);
        for (let i = 0; i < likes.length; i++) {
            if (likes[i] in likeMap) return likeMap[likes[i]];
        }

        // Tier 3: name substring matching for unrecognised IDs
        if (name.includes("endeavouros")) return "endeavouros";
        if (name.includes("nixos")) return "nixos";
        if (name.includes("opensuse")) return "opensuse";
        if (name.includes("manjaro")) return "manjaro";
        if (name.includes("zorin")) return "zorin-os";
        if (name.includes("rocky linux")) return "rockylinux";
        if (name.includes("centos")) return "centos";
        if (name.includes("red hat")) return "redhat";
        if (name.includes("alpine")) return "alpine";
        if (name.includes("gentoo")) return "gentoo";
        if (name.includes("mint")) return "mint";
        if (name.includes("pop")) return "pop-os";
        if (name.includes("ubuntu")) return "ubuntu";
        if (name.includes("debian")) return "debian";
        if (name.includes("arch")) return "arch";
        if (name.includes("fedora")) return "fedora";

        return "fedora";
    }

    RippleButton {
        id: titleButton
        anchors.fill: parent
        // Match the pill-shaped hover of BarTextButton (workspaces /
        // applications): full-height radius + same 0.10 white fill, so
        // every left-bar button's hover looks identical.
        buttonRadius: parent.height / 2
        colBackground: "transparent"
        colBackgroundHover: Qt.rgba(1, 1, 1, 0.10)
        colBackgroundToggled: Qt.rgba(1, 1, 1, 0.18)
        colBackgroundToggledHover: Qt.rgba(1, 1, 1, 0.26)
        colRipple: Qt.rgba(1, 1, 1, 0.12)
        toggled: windowMenu.item != null

        onClicked: {
            console.log("[ActiveWindow] clicked visible=", root.visible,
                "shortened=", root.useShortenedForm,
                "target=", root.focusedToplevel?.appId ?? "null");
            // Toggle: second click on the title closes the menu.
            const menu = windowMenu.item;
            if (menu !== null && menu.visible) {
                console.log("[ActiveWindow] toggle->closing");
                menu.close();
                return;
            }
            console.log("[ActiveWindow] toggle->opening");
            root.menuTarget = root.focusedToplevel;
            windowMenu.open();
        }
    }

    RowLayout {
        id: contentRow
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 6

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 14
            implicitHeight: 14

            IconImage {
                id: windowIcon
                anchors.fill: parent
                visible: root.hasWindowOnWorkspace ? root.windowIconClass.length > 0 : true
                source: root.hasWindowOnWorkspace ? AppSearch.iconSource(AppSearch.guessIcon(root.windowIconClass)) : root.osIconPath
                smooth: true
            }

            Rectangle {
                anchors.fill: parent
                visible: !windowIcon.visible || windowIcon.source === "" || windowIcon.status === Image.Error
                radius: 3
                color: "transparent"

                StyledText {
                    anchors.centerIn: parent
                    text: root.fallbackLetter(root.windowIconClass, root.displayTitle)
                    font.pixelSize: 9
                    font.variableAxes: ({ "wght": 700 })
                    color: Appearance.colors.colBarText
                }
            }
        }

        StyledText {
            id: titleText
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            // fillWidth lets the text shrink/elide when root is capped at
            // titleAreaWidth; maximumWidth caps its share at the content
            // budget (280 - padding 20 - icon 14 - spacing 6 = 240).
            Layout.maximumWidth: root.maxContentWidth
            font.pixelSize: 12
            font.variableAxes: ({
                "wght": 500,
                "wdth": 100,
            })
            color: Appearance.colors.colBarText
            elide: Text.ElideRight
            maximumLineCount: 1
            text: root.displayTitle
        }
    }

    BarContextMenu {
        id: windowMenu
        anchorItem: titleButton
        sourceComponent: ActiveWindowMenu {
            targetToplevel: root.menuTarget
        }
    }
}
