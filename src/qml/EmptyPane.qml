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

    Accessible.ignored: !visible
    implicitWidth: Kirigami.Units.gridUnit * 24
    implicitHeight: content.implicitHeight

    ColumnLayout {
        id: content
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 3, Kirigami.Units.gridUnit * 24)
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large
                visible: root.actionText.length === 0 && root.actionIcon.length > 0
                source: root.actionIcon
                Accessible.ignored: true
            }

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
            Accessible.ignored: !visible
            text: root.actionText
            icon.name: root.actionIcon
            onClicked: root.actionTriggered()
        }
    }
}
