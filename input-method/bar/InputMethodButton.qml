import qs
import qs.modules.inputMethod as InputMethodMod
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
BarModuleButton {
    id: root

    icon: NerdIconMap.keyboard
    iconColor: Appearance.colors.colBarText
    visible: Config.options.inputMethod.enabled && InputMethodMod.InputMethod.available
    active: GlobalStates.barPopupType === "inputMethod"

    onClicked: {
        if (Date.now() - GlobalStates.barPopupDismissedAt < 200) return;
        InputMethodMod.InputMethod.refresh();
        GlobalStates.barPopupType = GlobalStates.barPopupType === "inputMethod" ? "" : "inputMethod";
    }
}
