import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Item {
    id: root

    property url source: ""
    property string fallbackText: "?"
    property string fallbackIcon: ""
    property color backgroundColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                              Kirigami.Theme.textColor.g,
                                              Kirigami.Theme.textColor.b, 0.07)
    property color fallbackColor: Kirigami.Theme.textColor
    property real cornerRadius: 12

    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.backgroundColor
    }

    Image {
        id: avatarSource
        anchors.fill: parent
        visible: false
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
    }

    Rectangle {
        id: avatarMask
        anchors.fill: parent
        visible: false
        radius: root.cornerRadius
        color: "white"
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.source.toString().length > 0
        source: avatarSource
        maskEnabled: true
        maskSource: avatarMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: Math.min(root.width, root.height) * 0.44
        height: width
        visible: root.source.toString().length === 0 && root.fallbackIcon.length > 0
        source: root.fallbackIcon
        color: root.fallbackColor
    }

    Controls.Label {
        anchors.centerIn: parent
        visible: root.source.toString().length === 0 && root.fallbackIcon.length === 0
        text: root.fallbackText
        color: root.fallbackColor
        font.weight: Font.DemiBold
        font.pixelSize: Math.max(12, Math.min(root.width, root.height) * 0.36)
    }
}
