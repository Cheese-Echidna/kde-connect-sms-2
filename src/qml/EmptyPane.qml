import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: root

    property string title: ""
    property string description: ""
    property string actionText: ""
    property string actionIcon: ""
    signal actionTriggered()

    implicitWidth: Kirigami.Units.gridUnit * 24
    implicitHeight: content.implicitHeight

    ColumnLayout {
        id: content
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 3, Kirigami.Units.gridUnit * 24)
        spacing: Kirigami.Units.largeSpacing

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            radius: 18
            color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                           Kirigami.Theme.highlightColor.g,
                           Kirigami.Theme.highlightColor.b, 0.12)

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.medium
                height: width
                source: root.actionIcon.length > 0 ? root.actionIcon : "kdeconnect"
                color: Kirigami.Theme.highlightColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                Layout.fillWidth: true
                text: root.title
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 20
                font.weight: Font.DemiBold
            }

            Controls.Label {
                Layout.fillWidth: true
                text: root.description
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                opacity: 0.62
                lineHeight: 1.15
            }
        }

        Controls.Button {
            Layout.alignment: Qt.AlignHCenter
            visible: root.actionText.length > 0
            text: root.actionText
            icon.name: root.actionIcon
            onClicked: root.actionTriggered()
        }
    }
}
