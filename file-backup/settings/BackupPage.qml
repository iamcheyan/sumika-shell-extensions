import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings
import qs.modules.settings.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

PageBody {
    id: pageRoot
    property var settingsRoot: null

    SettingsCard {
        title: "File Share / Backup"
        subtitle: "SMB backup, sync and file sharing"

        ButtonRow {
            SettingsButton {
                label: "Open Backup Settings"
                iconName: "cloud_upload"
                onClicked: {
                    if (settingsRoot) settingsRoot.dismiss();
                    Quickshell.execDetached([`${FileUtils.trimFileProtocol(Directories.config)}/omd/bin/sumika-launch-settings-backup-tui`]);
                }
            }
        }
    }
}
