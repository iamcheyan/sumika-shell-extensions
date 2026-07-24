pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

PopupWindow {
    id: root

    property string shareDir: FileUtils.trimFileProtocol(Qt.resolvedUrl("..")) + "/bin"

    // Style tokens aligned with TuiStyle and GNOME-style appearance
    readonly property int   itemHeight:      36
    readonly property int   itemRadius:       6
    readonly property int   iconColumnWidth: 20
    readonly property int   iconSize:        18
    readonly property real  hPadding:        10
    readonly property real  menuPadding:      6
    readonly property real  outerPadding:     Appearance.sizes.elevationMargin

    signal menuClosed()

    color: "transparent"

    implicitWidth:  popupBackground.implicitWidth  + root.outerPadding * 2
    implicitHeight: popupBackground.implicitHeight + root.outerPadding * 2

    function open()  {
        root.visible = true;
    }

    function close() {
        root.visible = false;
        root.menuClosed();
    }

    Component.onDestruction: {
        dismissGuard.stop();
        GlobalFocusGrab.removeDismissable(root);
    }

    Timer {
        id: dismissGuard
        interval: 50
        repeat: false
        onTriggered: {
            if (root.visible)
                GlobalFocusGrab.addDismissable(root);
        }
    }

    onVisibleChanged: {
        if (visible) {
            dismissGuard.restart();
        } else {
            dismissGuard.stop();
            GlobalFocusGrab.removeDismissable(root);
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            root.close()
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onPressed: event => {
            const pos = mapToItem(popupBackground, event.x, event.y)
            if (pos.x < 0 || pos.x > popupBackground.width || pos.y < 0 || pos.y > popupBackground.height)
                root.close();
        }

        StyledRectangularShadow {
            target:  popupBackground
            opacity: popupBackground.opacity
        }

        Rectangle {
            id: popupBackground
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: root.outerPadding
            }
            color:        TuiStyle.bg
            radius:       TuiStyle.shellRadius
            border.width: TuiStyle.borderWidth
            border.color: TuiStyle.menuBorder
            clip:         true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: popupBackground.width
                    height: popupBackground.height
                    radius: popupBackground.radius
                }
            }

            opacity: 0
            Component.onCompleted: opacity = 1
            implicitWidth:  columnLayout.implicitWidth  + root.menuPadding * 2
            implicitHeight: columnLayout.implicitHeight + root.menuPadding * 2

            Behavior on opacity        { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(popupBackground) }
            Behavior on implicitHeight { animation: Appearance.animation.elementResize.numberAnimation.createObject(popupBackground) }
            Behavior on implicitWidth  { animation: Appearance.animation.elementResize.numberAnimation.createObject(popupBackground) }

            ColumnLayout {
                id: columnLayout
                anchors {
                    fill:    parent
                    margins: root.menuPadding
                }
                spacing: 0

                // MenuItem helper component defined inline
                component MenuItem : RippleButton {
                    id: itemRoot
                    property string menuIcon: ""
                    property string label: ""
                    property string sublabel: ""
                    property color color: TuiStyle.fg

                    buttonRadius:      root.itemRadius
                    horizontalPadding: root.hPadding
                    topPadding:        4
                    bottomPadding:     4
                    implicitHeight:    root.itemHeight
                    height:            root.itemHeight
                    Layout.fillWidth:  true

                    colBackground:      "transparent"
                    colBackgroundHover: TuiStyle.surfaceHover
                    colRipple:          TuiStyle.surfacePressed
                    borderWidth:        0

                    contentItem: RowLayout {
                        spacing: 10
                        Item {
                            Layout.preferredWidth:  root.iconColumnWidth
                            Layout.preferredHeight: root.iconColumnWidth
                            Layout.alignment:       Qt.AlignVCenter
                            NerdIcon {
                                anchors.centerIn: parent
                                iconSize: root.iconSize
                                text:     itemRoot.menuIcon
                                color:    itemRoot.color
                                visible:  itemRoot.menuIcon !== ""
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text:             itemRoot.label
                                color:            itemRoot.color
                                elide:            Text.ElideRight
                                font {
                                    pixelSize: 13
                                    weight:    Font.Medium
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text:             itemRoot.sublabel
                                color:            TuiStyle.fgMuted
                                elide:            Text.ElideRight
                                visible:          itemRoot.sublabel !== ""
                                font {
                                    pixelSize: 10
                                    weight:    Font.Normal
                                }
                            }
                        }
                    }
                }

                // Separator helper component defined inline
                component Separator : Rectangle {
                    Layout.fillWidth:    true
                    implicitHeight:      1
                    color:               TuiStyle.line
                    opacity:             TuiStyle.dividerOpacity
                    Layout.topMargin:    4
                    Layout.bottomMargin: 4
                }

                MenuItem {
                    menuIcon: NerdIconMap.cpu
                    label: "离线模型管理 & 检测 (TUI)"
                    sublabel: "SenseVoice 模型下载、检测与重装"
                    onClicked: {
                        Quickshell.execDetached([root.shareDir + "/omd-launch-settings-voice-tui"]);
                        root.close();
                    }
                }

                Separator {}

                MenuItem {
                    menuIcon: NerdIconMap.keyboard
                    label: "配置文件 / 快捷键设置"
                    sublabel: "编辑 ~/.config/voice_bindings.txt"
                    onClicked: {
                        Quickshell.execDetached([root.shareDir + "/omd-edit-voice-bindings"]);
                        root.close();
                    }
                }
            }
        }
    }
}
