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

Window {
    id: root

    title: "screenshot-context-menu"

    // Style tokens aligned with TuiStyle and GNOME-style appearance
    readonly property int   itemHeight:      32
    readonly property int   itemRadius:       6
    readonly property int   iconColumnWidth: 20
    readonly property int   iconSize:        18
    readonly property real  hPadding:         8
    readonly property real  menuPadding:      4
    readonly property real  outerPadding:     Appearance.sizes.elevationMargin

    signal menuClosed()

    color: "transparent"
    flags: Qt.FramelessWindowHint

    width:  popupBackground.implicitWidth  + root.outerPadding * 2
    height: popupBackground.implicitHeight + root.outerPadding * 2

    function open()  {
        root.visible = true;
    }

    function close() {
        root.visible = false;
        root.menuClosed();
    }

    onActiveChanged: {
        if (!root.active && root.visible)
            root.close();
    }

    Component.onCompleted: root.open()

    Shortcut {
        sequence: "Escape"
        onActivated: root.close()
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
                    property color color: TuiStyle.fg

                    buttonRadius:      root.itemRadius
                    horizontalPadding: root.hPadding
                    topPadding:        0
                    bottomPadding:     0
                    implicitHeight:    root.itemHeight
                    height:            root.itemHeight
                    Layout.fillWidth:  true

                    colBackground:      "transparent"
                    colBackgroundHover: TuiStyle.surfaceHover
                    colRipple:          TuiStyle.surfacePressed
                    borderWidth:        0

                    contentItem: RowLayout {
                        spacing: 8
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
                        StyledText {
                            Layout.fillWidth: true
                            text:             itemRoot.label
                            color:            itemRoot.color
                            elide:            Text.ElideRight
                            font {
                                pixelSize: 13
                                weight:    Font.Normal
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
                    menuIcon: NerdIconMap.screenshot
                    label: "Capture Area"
                    onClicked: {
                        Quickshell.execDetached(["omd-screenshot", "screenshot"]);
                        root.close();
                    }
                }

                MenuItem {
                    menuIcon: NerdIconMap.edit
                    label: "Capture & Edit"
                    onClicked: {
                        Quickshell.execDetached(["omd-screenshot", "edit"]);
                        root.close();
                    }
                }

                MenuItem {
                    menuIcon: NerdIconMap.camera
                    label: "Capture Fullscreen"
                    onClicked: {
                        Quickshell.execDetached(["bash", "-c",
                            "grim -o $(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name') - | wl-copy && notify-send -i camera-photo Screenshot \"Full screen copied to clipboard\""
                        ]);
                        root.close();
                    }
                }

                MenuItem {
                    menuIcon: NerdIconMap.desktop
                    label: "Capture Monitor (3s delay)"
                    onClicked: {
                        Quickshell.execDetached(["bash", "-c",
                            "monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'); notify-send -i camera-photo Screenshot \"Capturing current monitor in 3 seconds\"; sleep 3; grim -o \"$monitor\" - | wl-copy && notify-send -i camera-photo Screenshot \"Current monitor copied to clipboard\""
                        ]);
                        root.close();
                    }
                }

                Separator {}

                MenuItem {
                    menuIcon: NerdIconMap.eyeDropper
                    label: "Color Picker"
                    onClicked: {
                        Quickshell.execDetached(["hyprpicker", "-a"]);
                        root.close();
                    }
                }

                MenuItem {
                    menuIcon: NerdIconMap.video
                    label: "Record Screen"
                    onClicked: {
                        Quickshell.execDetached(["omd-screenshot", "record"]);
                        root.close();
                    }
                }

                Separator {}

                MenuItem {
                    menuIcon: NerdIconMap.textDocument
                    label: "OCR Recognize"
                    onClicked: {
                        Quickshell.execDetached(["omd-screenshot", "ocr"]);
                        root.close();
                    }
                }

                MenuItem {
                    menuIcon: NerdIconMap.settings
                    label: "OCR Settings"
                    onClicked: {
                        Quickshell.execDetached(["omd-launch-ocr-tui"]);
                        root.close();
                    }
                }
            }
        }
    }
}
