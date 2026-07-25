import QtQuick

import qs.modules.filebackup as FileBackupMod
import qs.core.runtime

Item {
    Component.onCompleted: {
        var fb = FileBackupMod.FileBackup

        ActionManager.register("file-backup.settings", "filebackup",
            "Open File Backup settings", {
            type: "qml",
            call: function(p) {
                fb.openSettings()
            }
        }, {description: "Open or focus the File Backup settings page"})

        ActionManager.register("file-backup.refresh", "filebackup",
            "Refresh backup status", {
            type: "qml",
            call: function(p) {
                fb.refreshStatus()
            }
        }, {description: "Re-check backup connection and status"})

        ActionManager.register("file-backup.toggle", "filebackup",
            "Toggle backup popup", {
            type: "qml",
            call: function(p) {
                fb.togglePopup()
            }
        }, {description: "Show or hide the backup popup"})
    }
}
