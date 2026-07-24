import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

BarModuleButton {
    icon: NerdIconMap.crop
    active: false
    onClicked: {
        Quickshell.execDetached(["omd-screenshot"]);
    }
}
