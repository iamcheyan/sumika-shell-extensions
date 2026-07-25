import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.windowsvm as WindowsVmMod
import QtQuick

BarModuleButton {
    icon: NerdIconMap.desktop
    active: GlobalStates.barPopupType === "windows-vm"
    readonly property bool __vmInit: WindowsVmMod.WindowsVm === null ? false : true
    onClicked: {
        if (Date.now() - GlobalStates.barPopupDismissedAt < 200) return;
        GlobalStates.barPopupType = GlobalStates.barPopupType === "windows-vm" ? "" : "windows-vm";
    }
}
