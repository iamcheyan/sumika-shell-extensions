import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.bar

PopupColumn {
    PopupHeader {
        Layout.fillWidth: true
        icon: NerdIconMap.desktop
        title: "Windows VM"
        subtitle: "Virtual machine management"
    }
    ToolLauncherRow {
        Layout.fillWidth: true
        icon: "desktop_windows"
        title: "VM Settings"
        subtitle: "Install, run and manage Windows"
        onClicked: {
            root.close();
            Quickshell.execDetached(["sumika-launch-settings-windows-tui"]);
        }
    }
}
