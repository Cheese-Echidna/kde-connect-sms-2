import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var devices: []
    property var conversations: []
    property string selectedDevice: ""
    property double selectedThread: -1
    property bool busy: false
    property bool phoneConnected: false
    property bool connectionChecked: false
    property string statusMessage: ""

    signal deviceSelected(string deviceId)
    signal conversationSelected(double threadId)
    signal newConversation()
    signal refreshRequested()

    color: Kirigami.Theme.alternateBackgroundColor

    function translucent(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function activeDeviceName() {
        for (let index = 0; index < devices.length; index++) {
            if (devices[index].id === selectedDevice)
                return devices[index].name
        }
        return devices.length > 0 ? devices[0].name : "Phone"
    }

    function connectionTitle() {
        if (!connectionChecked)
            return "Checking phone connection"
        return phoneConnected ? "Phone connected" : "Phone disconnected"
    }

    function filteredConversations() {
        const query = searchField.text.trim().toLowerCase()
        if (!query)
            return conversations
        return conversations.filter(item =>
            item.title.toLowerCase().includes(query) || item.preview.toLowerCase().includes(query))
    }

    function conversationDate(timestamp) {
        const date = new Date(timestamp)
        const now = new Date()
        if (date.toDateString() === now.toDateString())
            return Qt.formatTime(date, "h:mm AP")

        const yesterday = new Date(now)
        yesterday.setDate(now.getDate() - 1)
        if (date.toDateString() === yesterday.toDateString())
            return "Yesterday"
        if (date.getFullYear() === now.getFullYear())
            return Qt.formatDate(date, "MMM d")
        return Qt.formatDate(date, "MMM d, yyyy")
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.Label {
                    Layout.fillWidth: true
                    text: "Messages"
                    font.pixelSize: 21
                    font.weight: Font.DemiBold
                }

                Controls.Button {
                    icon.name: "mail-message-new"
                    text: "Compose"
                    onClicked: root.newConversation()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 9
                color: root.phoneConnected
                    ? root.translucent(Kirigami.Theme.highlightColor, 0.10)
                    : root.translucent(Kirigami.Theme.textColor, 0.05)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        source: !root.connectionChecked
                            ? "view-refresh"
                            : (root.phoneConnected ? "network-connect" : "network-disconnect")
                        color: root.phoneConnected
                            ? Kirigami.Theme.highlightColor
                            : Kirigami.Theme.textColor
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Controls.Label {
                            Layout.fillWidth: true
                            text: root.connectionTitle()
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Controls.Label {
                            Layout.fillWidth: true
                            text: root.phoneConnected
                                ? root.activeDeviceName() + " · " + root.statusMessage
                                : root.statusMessage
                            color: Kirigami.Theme.textColor
                            opacity: 0.60
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Controls.ToolButton {
                        icon.name: "view-refresh"
                        display: Controls.AbstractButton.IconOnly
                        enabled: !root.busy
                        Controls.ToolTip.text: "Check phone connection"
                        Controls.ToolTip.visible: hovered
                        Accessible.name: Controls.ToolTip.text
                        onClicked: root.refreshRequested()
                    }
                }
            }

            Controls.ComboBox {
                Layout.fillWidth: true
                visible: root.devices.length > 1
                textRole: "name"
                valueRole: "id"
                model: root.devices
                Accessible.name: "Connected phone"
                onActivated: root.deviceSelected(currentValue)
            }

            Controls.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "Search messages"
                leftPadding: Kirigami.Units.gridUnit * 2
                Accessible.name: "Search conversations"

                Kirigami.Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    source: "search"
                    color: Kirigami.Theme.textColor
                    opacity: 0.55
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.smallSpacing
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth

            ListView {
                id: listView
                model: root.filteredConversations()
                spacing: 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Controls.ItemDelegate {
                    id: conversationDelegate
                    required property var modelData

                    width: ListView.view.width
                    height: 74
                    leftPadding: Kirigami.Units.largeSpacing
                    rightPadding: Kirigami.Units.largeSpacing
                    activeFocusOnTab: true
                    onClicked: root.conversationSelected(modelData.threadId)

                    background: Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        radius: 10
                        color: modelData.threadId === root.selectedThread
                            ? root.translucent(Kirigami.Theme.highlightColor, 0.18)
                            : (conversationDelegate.hovered
                                ? root.translucent(Kirigami.Theme.textColor, 0.06)
                                : "transparent")
                        border.width: conversationDelegate.activeFocus ? 2 : 0
                        border.color: Kirigami.Theme.highlightColor

                        Behavior on color {
                            ColorAnimation { duration: 160 }
                        }
                    }

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing

                        RoundedAvatar {
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46
                            cornerRadius: 14
                            source: modelData.avatar || ""
                            fallbackText: modelData.title.length > 0
                                ? modelData.title.charAt(0).toUpperCase()
                                : "?"
                            backgroundColor: modelData.threadId === root.selectedThread
                                ? root.translucent(Kirigami.Theme.highlightColor, 0.22)
                                : root.translucent(Kirigami.Theme.textColor, 0.07)
                            fallbackColor: modelData.threadId === root.selectedThread
                                ? Kirigami.Theme.highlightColor
                                : Kirigami.Theme.textColor
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Controls.Label {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    elide: Text.ElideRight
                                    font.weight: Font.DemiBold
                                }

                                Controls.Label {
                                    text: root.conversationDate(modelData.timestamp)
                                    color: Kirigami.Theme.textColor
                                    opacity: 0.58
                                    font.pixelSize: 11
                                }
                            }

                            Controls.Label {
                                Layout.fillWidth: true
                                text: (modelData.outgoing ? "You: " : "") + modelData.preview
                                color: Kirigami.Theme.textColor
                                opacity: modelData.threadId === root.selectedThread ? 0.74 : 0.58
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, implicitWidth)
                    visible: listView.count === 0 && !root.busy
                    icon.name: searchField.text.length > 0 ? "search" : "mail-unread"
                    text: searchField.text.length > 0 ? "No matching conversations" : "No conversations yet"
                    explanation: searchField.text.length > 0
                        ? "Try a name, number, or words from a message."
                        : "Connect and unlock your phone, then refresh."
                }
            }
        }

        Controls.ProgressBar {
            Layout.fillWidth: true
            visible: root.busy
            indeterminate: true
            Accessible.name: "Refreshing conversations"
        }
    }
}
