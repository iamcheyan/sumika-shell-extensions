import qs.services
import qs.core.runtime
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root

    property int titleAreaWidth: 280
    property bool hideOnShortScreen: true

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property int activeWorkspaceId: ServiceManager.workspace?.monitorActiveWorkspaceId(root.monitor) ?? 0
    readonly property var displayClient: ServiceManager.workspace?.focusedClientForWorkspace(root.activeWorkspaceId) ?? null

    readonly property bool hasWindowOnWorkspace: root.displayClient !== null
    readonly property string windowTitle: root.displayClient?.title ?? ""
    readonly property string windowIconClass: root.displayClient?.class ?? ""
    readonly property string displayTitle: root.hasWindowOnWorkspace ? root.windowTitle : root.desktopDisplayName()
    readonly property string osIconPath: Qt.resolvedUrl("icons/" + root.osIconName() + ".svg")

    readonly property var screen: root.QsWindow.window?.screen
    readonly property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0

    implicitWidth: titleAreaWidth
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

    RowLayout {
        anchors.fill: parent
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
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
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
}
