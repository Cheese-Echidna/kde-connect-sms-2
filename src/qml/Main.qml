import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.sms2.backend

Kirigami.ApplicationWindow {
    id: root

    width: 1180
    height: 760
    minimumWidth: 420
    minimumHeight: 540
    visible: true
    title: "SMS2"
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    readonly property bool compactMode: width < 760
    readonly property var devices: parseJson(backend.devicesJson)
    readonly property var conversations: parseJson(backend.conversationsJson)
    readonly property var messages: parseJson(backend.messagesJson)
    property bool composingNew: false
    property bool startupSelectionPending: true

    function parseJson(value) {
        try {
            return JSON.parse(value || "[]")
        } catch (error) {
            return []
        }
    }

    function selectedConversation() {
        for (let index = 0; index < conversations.length; index++) {
            if (conversations[index].threadId === backend.selectedThread)
                return conversations[index]
        }
        return null
    }

    function translatedStatus(value) {
        const messages = {
            "Connecting to KDE Connect": qsTr("Connecting to KDE Connect"),
            "Showing cached messages": qsTr("Showing cached messages"),
            "Looking for phones": qsTr("Looking for phones"),
            "No reachable phone with SMS support": qsTr("No reachable phone with SMS support"),
            "Message not sent": qsTr("Message not sent"),
            "Syncing conversations and contacts": qsTr("Syncing conversations and contacts"),
            "Syncing messages": qsTr("Syncing messages"),
            "Up to date": qsTr("Up to date"),
            "Connection problem": qsTr("Connection problem"),
            "cache-unavailable": qsTr("Local cache unavailable")
        }
        return messages[value] || value
    }

    function translatedError(value) {
        const exact = {
            "Connect the phone to open the full image": qsTr("Connect the phone to open the full image"),
            "Choose a conversation before sending a message": qsTr("Choose a conversation before sending a message"),
            "Write a message or attach a file before sending": qsTr("Write a message or attach a file before sending"),
            "Connect a phone before sending a message": qsTr("Connect a phone before sending a message"),
            "Add at least one recipient before sending": qsTr("Add at least one recipient before sending"),
            "The phone did not return messages in time": qsTr("The phone did not return messages in time"),
            "KDE Connect stopped waiting for the image": qsTr("KDE Connect stopped waiting for the image"),
            "The phone did not return the full image in time": qsTr("The phone did not return the full image in time"),
            "Attachments must be 25 MB or smaller in total.": qsTr("Attachments must be 25 MB or smaller in total.")
        }
        if (exact[value])
            return exact[value]

        const prefixes = [
            ["Could not update the local cache:", qsTr("Could not update the local cache: %1")],
            ["Could not start the messaging service:", qsTr("Could not start the messaging service: %1")],
            ["Could not connect to KDE Connect:", qsTr("Could not connect to KDE Connect: %1")],
            ["The attachment no longer exists:", qsTr("The attachment no longer exists: %1")]
        ]
        for (let index = 0; index < prefixes.length; index++) {
            if (value.startsWith(prefixes[index][0]))
                return prefixes[index][1].arg(value.slice(prefixes[index][0].length).trim())
        }
        return translatedStatus(value)
    }

    function openMostRecentConversation() {
        if (!startupSelectionPending || composingNew || conversations.length === 0)
            return
        if (backend.selectedThread >= 0) {
            startupSelectionPending = false
            return
        }

        let mostRecent = conversations[0]
        for (let index = 1; index < conversations.length; index++) {
            if (conversations[index].timestamp > mostRecent.timestamp)
                mostRecent = conversations[index]
        }

        startupSelectionPending = false
        backend.openConversation(mostRecent.threadId)
    }

    onConversationsChanged: Qt.callLater(openMostRecentConversation)

    AppController {
        id: backend
    }

    Component.onCompleted: backend.initialize()

    Timer {
        interval: 20000
        repeat: true
        running: root.visible && backend.selectedThread >= 0 && !backend.busy && !backend.sending
        onTriggered: backend.refreshMessages()
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.visible && !backend.busy && !backend.sending
        onTriggered: backend.refreshConversations()
    }

    globalDrawer: Kirigami.GlobalDrawer {
        isMenu: true
        actions: [
            Kirigami.Action {
                text: qsTr("Refresh")
                icon.name: "view-refresh"
                enabled: !backend.busy
                onTriggered: backend.refreshConversations()
            }
        ]
    }

    pageStack.initialPage: Kirigami.Page {
        id: mainPage
        padding: 0
        title: qsTr("Messages")

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                ConversationList {
                    id: conversationList
                    Layout.preferredWidth: root.compactMode ? 0 : 370
                    Layout.minimumWidth: root.compactMode ? 0 : 300
                    Layout.fillWidth: root.compactMode
                    Layout.fillHeight: true
                    visible: !root.compactMode || (backend.selectedThread < 0 && !root.composingNew)
                    devices: root.devices
                    conversations: root.conversations
                    selectedDevice: backend.selectedDevice
                    selectedThread: backend.selectedThread
                    busy: backend.busy
                    phoneConnected: backend.phoneConnected
                    connectionChecked: backend.connectionChecked
                    statusMessage: root.translatedStatus(backend.statusMessage)
                    onDeviceSelected: deviceId => backend.selectDevice(deviceId)
                    onConversationSelected: threadId => {
                        root.startupSelectionPending = false
                        root.composingNew = false
                        backend.openConversation(threadId)
                    }
                    onNewConversation: {
                        root.startupSelectionPending = false
                        root.composingNew = true
                    }
                    onRefreshRequested: backend.refreshConversations()
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    visible: !root.compactMode
                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                   Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.10)
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.compactMode || backend.selectedThread >= 0 || root.composingNew

                    EmptyPane {
                        anchors.fill: parent
                        visible: backend.selectedThread < 0 && !root.composingNew
                        title: root.conversations.length > 0 ? qsTr("Choose a conversation") : qsTr("Your phone is ready")
                        description: root.conversations.length > 0
                            ? qsTr("Select a thread to read and reply.")
                            : qsTr("Messages from your paired phone will appear here after synchronization.")
                        actionText: root.conversations.length > 0 ? qsTr("New message") : qsTr("Refresh conversations")
                        actionIcon: root.conversations.length > 0 ? "mail-message-new" : "view-refresh"
                        onActionTriggered: {
                            if (root.conversations.length > 0)
                                root.composingNew = true
                            else
                                backend.refreshConversations()
                        }
                    }

                    ConversationPage {
                        id: conversationPage
                        anchors.fill: parent
                        visible: backend.selectedThread >= 0 || root.composingNew
                        compactMode: root.compactMode
                        conversation: root.selectedConversation()
                        messages: root.messages
                        newMode: root.composingNew
                        busy: backend.busy
                        sending: backend.sending
                        phoneConnected: backend.phoneConnected
                        connectionChecked: backend.connectionChecked
                        errorMessage: root.translatedError(backend.errorMessage)
                        downloadedImageSource: backend.attachmentSource
                        downloadedImageName: backend.attachmentName
                        imageLoading: backend.attachmentLoading
                        attachmentValidator: paths => backend.validateAttachments(JSON.stringify(paths))
                        onBackRequested: {
                            root.composingNew = false
                            backend.openConversation(-1)
                        }
                        onReplyRequested: (text, attachments) => backend.sendReply(text, JSON.stringify(attachments))
                        onNewMessageRequested: (addresses, text, attachments) => {
                            backend.sendNew(JSON.stringify(addresses), text, JSON.stringify(attachments))
                        }
                        onNewMessageCompleted: root.composingNew = false
                        onRefreshRequested: backend.refreshMessages()
                        onFullImageRequested: (partId, uniqueIdentifier) => {
                            backend.downloadAttachment(partId, uniqueIdentifier)
                        }
                        onCopyImageRequested: dataUrl => {
                            if (!backend.copyImage(dataUrl))
                                backend.reportError(qsTr("Could not copy the image."))
                        }
                        onSaveImageRequested: (dataUrl, fileUrl) => {
                            if (!backend.saveImage(dataUrl, fileUrl))
                                backend.reportError(qsTr("Could not save the image to the selected location."))
                        }
                    }
                }
            }
        }

        Kirigami.InlineMessage {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            z: 20
            visible: backend.errorMessage.length > 0
            type: Kirigami.MessageType.Error
            text: root.translatedError(backend.errorMessage)
            showCloseButton: true
            onVisibleChanged: {
                if (!visible)
                    backend.clearError()
            }
        }
    }
}
