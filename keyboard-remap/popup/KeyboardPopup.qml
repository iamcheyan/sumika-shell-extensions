import qs.modules.bar
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

PopupColumn {
    id: keyboardPanel

    KeyboardRemap {
        id: kr
        visible: false
    }

    function stateLabel() {
        if (kr.state === "setup") return "Setup needed";
        if (!kr.keydReady) return "keyd not running";
        if (kr.selectedDeviceId) return "Ready";
        return "No device";
    }
    function tone() {
        if (stateLabel() === "Ready") return TuiStyle.success;
        if (stateLabel() === "Setup needed" || stateLabel() === "keyd not running") return TuiStyle.danger;
        return TuiStyle.muted;
    }

    PopupHeader {
        Layout.fillWidth: true
        icon: NerdIconMap.wrench
        title: "Keyboard"
        subtitle: keyboardPanel.stateLabel()
        tone: keyboardPanel.tone()
    }

    PopupInfoRow { label: "Device"; value: kr.selectedDeviceId || "--"; valueColor: kr.selectedDeviceId ? TuiStyle.fg : TuiStyle.dim }
    PopupInfoRow { label: "Keyd"; value: kr.keydReady ? "Running" : "Not ready"; valueColor: kr.keydReady ? TuiStyle.success : TuiStyle.danger }
    PopupInfoRow {
        label: "Profile"
        value: kr.selectedProfile?.displayName || "--"
        valueColor: kr.selectedProfile ? TuiStyle.accent : TuiStyle.dim
        showDivider: false
    }

    PopupFooterLink {
        Layout.fillWidth: true
        label: "Keyboard settings…"
        onClicked: {
            root.close();
            Quickshell.execDetached(["sumika-launch-keyboard-tui"]);
        }
    }
}
