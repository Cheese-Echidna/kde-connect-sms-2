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
    enabled: visible
    Accessible.ignored: !visible

    ListModel {
        id: conversationModel
        dynamicRoles: true
    }

    function conversationIndex(threadId, startIndex) {
        for (let index = startIndex; index < conversationModel.count; index++) {
            if (conversationModel.get(index).threadId === threadId)
                return index
        }
        return -1
    }

    function syncConversations() {
        for (let target = 0; target < conversations.length; target++) {
            const item = conversations[target]
            const existing = conversationIndex(item.threadId, target)
            if (existing < 0)
                conversationModel.insert(target, item)
            else if (existing !== target)
                conversationModel.move(existing, target, 1)
            conversationModel.set(target, item)
        }
        while (conversationModel.count > conversations.length)
            conversationModel.remove(conversationModel.count - 1)
    }

    onConversationsChanged: syncConversations()
    Component.onCompleted: syncConversations()

    function translucent(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function activeDeviceName() {
        for (let index = 0; index < devices.length; index++) {
            if (devices[index].id === selectedDevice)
                return devices[index].name
        }
        return devices.length > 0 ? devices[0].name : qsTr("Phone")
    }

    function connectionTitle() {
        if (!connectionChecked)
            return qsTr("Checking phone connection")
        return phoneConnected ? qsTr("Phone connected") : qsTr("Phone disconnected")
    }

    function filteredConversations() {
        const query = searchField.text.trim().toLowerCase()
        if (!query)
            return conversationModel
        const matches = []
        for (let index = 0; index < conversationModel.count; index++) {
            const item = conversationModel.get(index)
            const participants = (item.participants || []).join(" ").toLowerCase()
            if (item.title.toLowerCase().includes(query)
                    || item.preview.toLowerCase().includes(query)
                    || participants.includes(query))
                matches.push(item)
        }
        return matches
    }

    function conversationDate(timestamp) {
        const date = new Date(timestamp)
        const now = new Date()
        if (date.toDateString() === now.toDateString())
            return date.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)

        const yesterday = new Date(now)
        yesterday.setDate(now.getDate() - 1)
        if (date.toDateString() === yesterday.toDateString())
            return qsTr("Yesterday")
        return date.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
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
                    text: qsTr("Messages")
                    font.pixelSize: 21
                    font.weight: Font.DemiBold
                }

                Controls.Button {
                    text: qsTr("Compose")
                    Accessible.ignored: !root.visible
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

                    Controls.Button {
                        text: qsTr("Check")
                        flat: true
                        enabled: !root.busy
                        Accessible.name: qsTr("Check phone connection")
                        Accessible.ignored: !root.visible
                        onClicked: root.refreshRequested()
                    }
                }
            }

            Controls.ComboBox {
                Layout.fillWidth: true
                visible: root.devices.length > 1
                Accessible.ignored: !visible || !root.visible
                textRole: "name"
                valueRole: "id"
                model: root.devices
                Accessible.name: qsTr("Connected phone")
                onActivated: root.deviceSelected(currentValue)
            }

            Controls.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: qsTr("Search messages")
                rightPadding: clearSearchButton.visible ? clearSearchButton.width : Kirigami.Units.smallSpacing
                Accessible.name: qsTr("Search conversations")
                Accessible.ignored: !root.visible

                Controls.Button {
                    id: clearSearchButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchField.text.length > 0
                    text: qsTr("Clear")
                    flat: true
                    Accessible.name: qsTr("Clear search")
                    Accessible.ignored: !visible || !root.visible
                    onClicked: searchField.clear()
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
                    property var modelData: model.modelData === undefined ? model : model.modelData

                    width: ListView.view.width
                    height: 74
                    leftPadding: Kirigami.Units.largeSpacing
                    rightPadding: Kirigami.Units.largeSpacing
                    activeFocusOnTab: root.visible
                    Accessible.role: Accessible.Button
                    Accessible.ignored: !root.visible
                    Accessible.name: modelData.title + ". "
                        + ((modelData.outgoing ? qsTr("You: ") : "") + modelData.preview) + ". "
                        + root.conversationDate(modelData.timestamp)
                    Accessible.onPressAction: conversationDelegate.clicked()
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
                                ? (/[+0-9]/.test(modelData.title.charAt(0))
                                    ? modelData.title.replace(/\D/g, "").slice(-2)
                                    : modelData.title.charAt(0).toUpperCase())
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
                                    opacity: 0.76
                                    font.pixelSize: 11
                                }
                            }

                            Controls.Label {
                                Layout.fillWidth: true
                                text: (modelData.outgoing ? qsTr("You: ") : "") + modelData.preview
                                color: Kirigami.Theme.textColor
                                opacity: modelData.threadId === root.selectedThread ? 0.84 : 0.72
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
                    Accessible.ignored: !visible
                    icon.name: searchField.text.length > 0 ? "search" : "mail-unread"
                    text: searchField.text.length > 0 ? qsTr("No matching conversations") : qsTr("No conversations yet")
                    explanation: searchField.text.length > 0
                        ? qsTr("Try a name, number, or words from a message.")
                        : qsTr("Connect and unlock your phone, then refresh.")
                }
            }
        }

        Controls.ProgressBar {
            Layout.fillWidth: true
            Layout.preferredHeight: 3
            opacity: root.busy ? 1 : 0
            Accessible.ignored: !root.busy
            indeterminate: root.busy
            Accessible.name: qsTr("Refreshing conversations")
        }
    }
}
