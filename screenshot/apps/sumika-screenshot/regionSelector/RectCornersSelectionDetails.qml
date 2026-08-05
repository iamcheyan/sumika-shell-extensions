import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    required property real regionX
    required property real regionY
    required property real regionWidth
    required property real regionHeight
    required property real mouseX
    required property real mouseY
    required property color color
    property bool showAimLines: Config.options.regionSelector.rect.showAimLines
    // Recording uses the same solid frame as selection/edit, tinted with the
    // recording accent color, plus pulsing corner dots as a live indicator.
    property bool recordingActive: false
    property color accentColor: "#e53935"

    // The outside dim mask is owned exclusively by RegionSelection.OutsideMask
    // (one instance for screenshot, one for recording). This component only
    // draws the selection frame, corner dots, size label and aim lines, so the
    // mask can never be double-painted by two independent code paths.
    readonly property color effectiveBorderColor: root.recordingActive ? root.accentColor : root.color

    // Solid selection frame — same 2px/4-radius style as the post-phase crop
    // box so screenshot and recording share one visual language. Recording
    // tints it with the accent color; selection/edit uses the neutral border.
    // While recording, the frame is shifted half its stroke width OUTSIDE the
    // region so no border pixels fall inside the wf-recorder -g capture area.
    Rectangle {
        id: selectionBorder
        z: 9
        readonly property real inset: root.recordingActive ? -border.width / 2 : 0
        x: Math.round(root.regionX) + inset
        y: Math.round(root.regionY) + inset
        width: Math.round(root.regionWidth) - inset * 2
        height: Math.round(root.regionHeight) - inset * 2
        color: "transparent"
        border.color: root.effectiveBorderColor
        border.width: 2
        radius: 4
        opacity: 0.9
    }

    // Pulsing accent dots at the four corners during live recording — the
    // only state-specific ornament on top of the shared frame.
    Repeater {
        model: root.recordingActive ? 4 : 0
        Rectangle {
            required property int index
            readonly property real cx: (index === 0 || index === 2) ? root.regionX : root.regionX + root.regionWidth
            readonly property real cy: (index === 0 || index === 1) ? root.regionY : root.regionY + root.regionHeight
            x: cx - 7; y: cy - 7
            width: 14; height: 14; radius: 7
            color: root.accentColor
            border.width: 1.5
            border.color: Qt.rgba(1, 1, 1, 0.6)
            z: 11
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.25; duration: 700 }
                NumberAnimation { from: 0.25; to: 1; duration: 700 }
            }
        }
    }

    StyledText {
        z: 2
        anchors {
            top: selectionBorder.bottom
            right: selectionBorder.right
            margins: 8
        }
        color: root.effectiveBorderColor
        text: `${Math.round(root.regionWidth)} x ${Math.round(root.regionHeight)}`
    }

    // Coord lines
    Rectangle { // Vertical
        visible: root.showAimLines && !root.recordingActive
        opacity: 0.2
        z: 2
        x: root.mouseX
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: root.color
    }
    Rectangle { // Horizontal
        visible: root.showAimLines && !root.recordingActive
        opacity: 0.2
        z: 2
        y: root.mouseY
        anchors {
            left: parent.left
            right: parent.right
        }
        height: 1
        color: root.color
    }
}