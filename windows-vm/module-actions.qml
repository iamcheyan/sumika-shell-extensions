import QtQuick

import qs.modules.windowsvm as WindowsVmMod
import qs.core.runtime

Item {
    Component.onCompleted: {
        var vm = WindowsVmMod.WindowsVm

        ActionManager.register("windows-vm.settings", "windowsvm",
            "Open Windows VM settings", {
            type: "qml",
            call: function(p) {
                vm.openSettings()
            }
        }, {description: "Open or focus the Windows VM settings page"})

        ActionManager.register("windows-vm.refresh", "windowsvm",
            "Refresh Windows VM status", {
            type: "qml",
            call: function(p) {
                vm.refreshStatus()
            }
        }, {description: "Re-check VM status and requirements"})

        ActionManager.register("windows-vm.toggle", "windowsvm",
            "Toggle Windows VM popup", {
            type: "qml",
            call: function(p) {
                vm.togglePopup()
            }
        }, {description: "Show or hide the Windows VM popup"})
    }
}
