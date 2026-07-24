//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_IM_MODULE=fcitx

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../../regionSelector"

ShellRoot {
    id: root

    Component.onCompleted: {
        GlobalStates.regionSelectorOpen = true;
    }

    Connections {
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (!GlobalStates.regionSelectorOpen) {
                Qt.quit();
            }
        }
    }

    RegionSelector {}
}
