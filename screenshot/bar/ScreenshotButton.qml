import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    Layout.fillHeight: true
    implicitWidth: Config.options.bar.rightIconSlotWidth
    implicitHeight: Config.options.bar.rightIconSlotWidth

    RippleButton {
        id: button
        anchors.centerIn: parent
        width: Config.options.bar.rightIconSlotWidth
        height: Config.options.bar.rightIconSlotWidth
        buttonRadius: Config.options.bar.rightIconSlotWidth / 2

        colBackground: "transparent"
        colBackgroundHover: Qt.rgba(1, 1, 1, 0.10)
        colBackgroundToggled: Qt.rgba(1, 1, 1, 0.18)
        colBackgroundToggledHover: Qt.rgba(1, 1, 1, 0.26)
        colRipple: Qt.rgba(1, 1, 1, 0.12)
        colRippleToggled: Qt.rgba(1, 1, 1, 0.18)

        onClicked: {
            // Left click: quick screenshot (default action)
            Quickshell.execDetached(["omd-screenshot"]);
        }

        // Right click: open context menu
        altAction: function(event) {
            menuLoader.open();
        }
    }

    BarNerdIcon {
        anchors.centerIn: button
        text: NerdIconMap.camera
        color: Appearance.colors.colBarText
    }

    BarContextMenu {
        id: menuLoader
        anchorItem: button
        sourceComponent: ScreenshotContextMenu {}
    }
}
