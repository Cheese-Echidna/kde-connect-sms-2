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
        interval: 12000
        repeat: true
        running: root.visible && backend.selectedThread >= 0 && !backend.busy && !backend.sending
        onTriggered: backend.refreshMessages()
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.visible && !backend.busy && !backend.sending
        onTriggered: backend.refreshConversations()
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.visible && !backend.sending
        onTriggered: backend.hardResync()
    }

    globalDrawer: Kirigami.GlobalDrawer {
        isMenu: true
        actions: [
            Kirigami.Action {
                text: "Refresh"
                icon.name: "view-refresh"
                enabled: !backend.busy
                onTriggered: backend.refreshConversations()
            }
        ]
    }

    pageStack.initialPage: Kirigami.Page {
        padding: 0
        title: "Messages"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: backend.errorMessage.length > 0
                type: Kirigami.MessageType.Error
                text: backend.errorMessage
                showCloseButton: true
                onVisibleChanged: {
                    if (!visible)
                        backend.clearError()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                ConversationList {
                    id: conversationList
                    Layout.preferredWidth: root.compactMode ? parent.width : 370
                    Layout.fillHeight: true
                    visible: !root.compactMode || (backend.selectedThread < 0 && !root.composingNew)
                    devices: root.devices
                    conversations: root.conversations
                    selectedDevice: backend.selectedDevice
                    selectedThread: backend.selectedThread
                    busy: backend.busy
                    phoneConnected: backend.phoneConnected
                    connectionChecked: backend.connectionChecked
                    statusMessage: backend.statusMessage
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

                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.compactMode || backend.selectedThread >= 0 || root.composingNew
                    sourceComponent: backend.selectedThread >= 0 || root.composingNew ? conversationPageComponent : emptyPaneComponent
                }
            }
        }
    }

    Component {
        id: conversationPageComponent

        ConversationPage {
            conversation: root.selectedConversation()
            messages: root.messages
            newMode: root.composingNew
            busy: backend.busy
            sending: backend.sending
            phoneConnected: backend.phoneConnected
            connectionChecked: backend.connectionChecked
            errorMessage: backend.errorMessage
            downloadedImageSource: backend.attachmentSource
            downloadedImageName: backend.attachmentName
            imageLoading: backend.attachmentLoading
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
            onCopyImageRequested: dataUrl => backend.copyImage(dataUrl)
            onSaveImageRequested: (dataUrl, fileUrl) => backend.saveImage(dataUrl, fileUrl)
        }
    }

    Component {
        id: emptyPaneComponent

        EmptyPane {
            title: root.conversations.length > 0 ? "Choose a conversation" : "Your phone is ready"
            description: root.conversations.length > 0
                ? "Select a thread to read and reply."
                : "Messages from your paired phone will appear here after synchronization."
            actionText: root.conversations.length > 0 ? "New message" : "Refresh conversations"
            actionIcon: root.conversations.length > 0 ? "mail-message-new" : "view-refresh"
            onActionTriggered: {
                if (root.conversations.length > 0)
                    root.composingNew = true
                else
                    backend.refreshConversations()
            }
        }
    }
}
