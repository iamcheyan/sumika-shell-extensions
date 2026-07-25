import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.keyboardremap
import QtQuick
import Quickshell

BarModuleButton {
    id: root

    moduleId: "keyboardremap"
    icon: NerdIconMap.wrench
    iconColor: Appearance.colors.colBarText
    visible: true
    active: false

    // Force KeyboardRemap singleton instantiation (for desktop launcher lifecycle etc.)
    readonly property bool __krInit: KeyboardRemap ? true : false

    onClicked: {
        if (Date.now() - GlobalStates.barPopupDismissedAt < 200) return;
        Quickshell.execDetached(["omd-launch-keyboard-tui"]);
    }
}
