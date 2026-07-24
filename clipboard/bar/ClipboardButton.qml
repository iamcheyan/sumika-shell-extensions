import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

BarModuleButton {
    icon: NerdIconMap.contentPaste
    active: false
    onClicked: {
        if (Date.now() - GlobalStates.barPopupDismissedAt < 200) return;
        Quickshell.execDetached([
            "omd-clipboard",
            "toggle-at-bar"
        ]);
    }
}
