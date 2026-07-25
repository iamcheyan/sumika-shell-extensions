import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.filebackup as FileBackupMod
import QtQuick

BarModuleButton {
    icon: NerdIconMap.workspaceSnapshot
    active: GlobalStates.barPopupType === "backup"
    readonly property bool __fbInit: FileBackupMod.FileBackup === null ? false : true
    onClicked: {
        if (Date.now() - GlobalStates.barPopupDismissedAt < 200) return;
        GlobalStates.barPopupType = GlobalStates.barPopupType === "backup" ? "" : "backup";
    }
}
