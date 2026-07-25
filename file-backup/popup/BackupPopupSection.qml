import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.bar
import qs.modules.common.widgets

PopupColumn {
    PopupHeader {
        Layout.fillWidth: true
        icon: NerdIconMap.cloud_upload
        title: "File Share / Backup"
        subtitle: "SMB backup, sync and file sharing"
    }

    ToolLauncherRow {
        icon: "cloud_upload"
        title: "Backup Settings"
        subtitle: "Manage SMB shares and backups"
        onClicked: {
            Quickshell.execDetached([`${FileUtils.trimFileProtocol(Directories.config)}/omd/bin/omd-launch-settings-backup-tui`]);
        }
    }
}
