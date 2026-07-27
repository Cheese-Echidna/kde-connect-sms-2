import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var conversation: null
    property var messages: []
    property bool newMode: false
    property bool compactMode: false
    property bool busy: false
    property bool sending: false
    property bool phoneConnected: false
    property bool connectionChecked: false
    property string errorMessage: ""
    property var attachments: []
    property bool sendStarted: false
    property bool sendPending: false
    property string previewImageSource: ""
    property string previewImageName: qsTr("Image attachment")
    property string contextImageSource: ""
    property string contextImageName: qsTr("Image attachment")
    property string contextImageKey: ""
    property string contextImageMime: "image/png"
    property double contextImagePartId: -1
    property string downloadedImageSource: ""
    property string downloadedImageName: ""
    property bool imageLoading: false
    property var attachmentValidator: null
    property string attachmentError: ""
    property bool followLatest: true
    property var drafts: ({})
    property string activeDraftKey: ""

    Accessible.ignored: !visible

    signal backRequested()
    signal replyRequested(string text, var attachments)
    signal newMessageRequested(var addresses, string text, var attachments)
    signal newMessageCompleted()
    signal refreshRequested()
    signal copyImageRequested(string dataUrl)
    signal saveImageRequested(string dataUrl, string fileUrl)
    signal fullImageRequested(var partId, string uniqueIdentifier)

    color: Kirigami.Theme.backgroundColor
    enabled: visible

    onMessagesChanged: {
        if (followLatest)
            Qt.callLater(messageList.jumpToBottom)
    }
    Component.onCompleted: switchDraft()

    function translucent(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function messageDayKey(timestamp) {
        return new Date(timestamp).toDateString()
    }

    function messageDayLabel(timestamp) {
        const date = new Date(timestamp)
        const now = new Date()
        if (date.toDateString() === now.toDateString())
            return qsTr("Today")

        const yesterday = new Date(now)
        yesterday.setDate(now.getDate() - 1)
        if (date.toDateString() === yesterday.toDateString())
            return qsTr("Yesterday")
        return date.toLocaleDateString(Qt.locale(), Locale.LongFormat)
    }

    function attachmentKey(partId, identifier) {
        const threadId = conversation ? conversation.threadId : -1
        return String(threadId) + ":" + String(partId) + ":" + identifier
    }

    function setContextImage(source, name, mimeType, partId) {
        contextImageSource = source
        contextImageName = name || qsTr("Image attachment")
        contextImageMime = mimeType || "image/png"
        contextImagePartId = partId === undefined ? -1 : partId
        contextImageKey = attachmentKey(contextImagePartId, contextImageName)
    }

    function openImagePreview(source, name, partId) {
        setContextImage(source, name, contextImageMime, partId)
        previewImageSource = source
        previewImageName = name || qsTr("Image attachment")
        imagePreview.open()
        if (contextImagePartId >= 0 && phoneConnected)
            fullImageRequested(contextImagePartId, contextImageName)
    }

    function showImageMenu(source, name, mimeType, partId) {
        setContextImage(source, name, mimeType, partId)
        imageMenu.popup()
    }

    onDownloadedImageSourceChanged: {
        if (downloadedImageSource && downloadedImageName === contextImageKey) {
            contextImageSource = downloadedImageSource
            previewImageSource = downloadedImageSource
        }
    }

    function currentDraftKey() {
        if (newMode)
            return "new"
        return conversation ? "thread:" + String(conversation.threadId) : ""
    }

    function saveActiveDraft() {
        if (!activeDraftKey)
            return
        drafts[activeDraftKey] = {
            text: messageField.text,
            attachments: attachments.slice(),
            recipients: activeDraftKey === "new" ? recipientsField.text : ""
        }
    }

    function restoreDraft(key) {
        const draft = drafts[key] || { text: "", attachments: [], recipients: "" }
        messageField.text = draft.text || ""
        attachments = (draft.attachments || []).slice()
        recipientsField.text = draft.recipients || ""
        attachmentError = ""
    }

    function switchDraft() {
        const nextKey = currentDraftKey()
        if (nextKey !== activeDraftKey) {
            saveActiveDraft()
            activeDraftKey = nextKey
            restoreDraft(nextKey)
        }
        if (newMode)
            composeFocusTimer.restart()
    }

    Timer {
        id: composeFocusTimer
        interval: 0
        onTriggered: recipientsField.forceActiveFocus(Qt.TabFocusReason)
    }

    function clearActiveDraft() {
        if (activeDraftKey)
            delete drafts[activeDraftKey]
        messageField.clear()
        attachments = []
        if (newMode)
            recipientsField.clear()
    }

    function recipientValues() {
        return recipientsField.text.split(/[;,]/).map(value => value.trim()).filter(Boolean)
    }

    function recipientIsValid(value) {
        const compact = value.replace(/[ ()-]/g, "")
        return /^\+?[0-9]{3,20}$/.test(compact)
    }

    function hasInvalidRecipient() {
        return recipientValues().some(value => !recipientIsValid(value))
    }

    function editFailedMessage(message) {
        messageField.text = message.body
        attachments = message.attachments
            .map(attachment => attachment.unique_identifier)
            .filter(Boolean)
        followLatest = true
        messageField.forceActiveFocus()
    }

    onConversationChanged: {
        switchDraft()
        followLatest = true
        Qt.callLater(messageList.jumpToBottom)
    }
    onNewModeChanged: switchDraft()

    function submit() {
        const text = messageField.text.trim()
        if (!text && attachments.length === 0)
            return

        attachmentError = attachmentValidator ? attachmentValidator(attachments) : ""
        if (attachmentError)
            return

        if (newMode) {
            const addresses = recipientValues()
            if (addresses.length === 0 || hasInvalidRecipient())
                return
            newMessageRequested(addresses, text, attachments)
        } else {
            replyRequested(text, attachments)
            clearActiveDraft()
        }
        sendPending = newMode
    }

    onSendingChanged: {
        if (sending && sendPending)
            sendStarted = true
        if (!sending && sendPending && sendStarted) {
            if (!errorMessage) {
                clearActiveDraft()
                if (newMode)
                    newMessageCompleted()
            }
            sendPending = false
            sendStarted = false
        }
    }

    Controls.Dialog {
        id: imagePreview

        parent: Controls.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 46)
        height: Math.min(parent.height - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 38)
        title: root.previewImageName
        modal: true
        standardButtons: Controls.Dialog.Close
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside

        contentItem: Rectangle {
            color: root.translucent(Kirigami.Theme.textColor, 0.04)
            radius: 10

            Image {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                source: root.previewImageSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: root.showImageMenu(
                        root.previewImageSource,
                        root.contextImageName,
                        root.contextImageMime,
                        root.contextImagePartId)
                }
            }

            Controls.BusyIndicator {
                anchors.centerIn: parent
                running: root.imageLoading
                visible: running
                Accessible.name: qsTr("Loading full image")
            }
        }
    }

    Controls.Menu {
        id: imageMenu

        Controls.MenuItem {
            text: qsTr("Open image")
            icon.name: "zoom-in"
            onTriggered: root.openImagePreview(
                root.contextImageSource,
                root.contextImageName,
                root.contextImagePartId)
        }

        Controls.MenuSeparator {}

        Controls.MenuItem {
            text: qsTr("Copy image")
            icon.name: "edit-copy"
            onTriggered: root.copyImageRequested(root.contextImageSource)
        }

        Controls.MenuItem {
            text: qsTr("Save image as…")
            icon.name: "document-save-as"
            onTriggered: saveImageDialog.open()
        }
    }

    FileDialog {
        id: saveImageDialog
        title: qsTr("Save image as")
        fileMode: FileDialog.SaveFile
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)", "All files (*)"]
        onAccepted: root.saveImageRequested(root.contextImageSource, String(selectedFile))
    }

    FileDialog {
        id: attachmentDialog
        title: qsTr("Attach files")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            const paths = []
            for (let index = 0; index < selectedFiles.length; index++) {
                const url = String(selectedFiles[index])
                paths.push(decodeURIComponent(url.replace(/^file:\/\//, "")))
            }
            const next = root.attachments.concat(paths)
            root.attachmentError = root.attachmentValidator ? root.attachmentValidator(next) : ""
            if (!root.attachmentError)
                root.attachments = next
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 68
            color: Kirigami.Theme.backgroundColor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing

                Controls.Button {
                    visible: root.compactMode || root.newMode
                    Accessible.ignored: !visible
                    icon.name: root.newMode ? "dialog-cancel" : "go-previous"
                    text: root.newMode ? qsTr("Cancel") : qsTr("Back")
                    flat: true
                    Accessible.name: root.newMode ? qsTr("Cancel new message") : qsTr("Back to conversations")
                    onClicked: root.backRequested()
                }

                RoundedAvatar {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    visible: !root.newMode
                    cornerRadius: 13
                    source: root.conversation && root.conversation.avatar
                        ? root.conversation.avatar
                        : ""
                    fallbackText: root.conversation && root.conversation.title.length > 0
                        ? (/[+0-9]/.test(root.conversation.title.charAt(0))
                            ? root.conversation.title.replace(/\D/g, "").slice(-2)
                            : root.conversation.title.charAt(0).toUpperCase())
                        : "?"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Controls.Label {
                        Layout.fillWidth: true
                        text: root.newMode ? qsTr("New message") : (root.conversation ? root.conversation.title : qsTr("Conversation"))
                        elide: Text.ElideRight
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: !root.newMode && root.conversation !== null
                        Accessible.ignored: !visible
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Label {
                            Layout.fillWidth: true
                            visible: root.conversation
                                && root.conversation.participants.join(" · ") !== root.conversation.title
                            Accessible.ignored: !visible
                            text: root.conversation ? root.conversation.participants.join(" · ") : ""
                            color: Kirigami.Theme.textColor
                            opacity: 0.72
                            elide: Text.ElideRight
                            font.pixelSize: 11
                        }

                        Controls.Label {
                            text: !root.connectionChecked
                                ? qsTr("Checking phone")
                                : (root.phoneConnected ? qsTr("Connected") : qsTr("Disconnected"))
                            color: root.phoneConnected
                                ? Kirigami.Theme.highlightColor
                                : Kirigami.Theme.textColor
                            opacity: root.phoneConnected ? 1.0 : 0.68
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Controls.Button {
                    visible: !root.newMode
                    Accessible.ignored: !visible || !root.visible
                    text: qsTr("Refresh")
                    flat: true
                    enabled: !root.busy
                    Accessible.name: qsTr("Refresh messages")
                    onClicked: root.refreshRequested()
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Kirigami.Theme.alternateBackgroundColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            visible: root.newMode
            Accessible.ignored: !visible
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: qsTr("To")
                font.weight: Font.DemiBold
            }

            Controls.TextField {
                id: recipientsField
                objectName: "recipientsField"
                Layout.fillWidth: true
                placeholderText: qsTr("Phone number, or separate recipients with commas")
                inputMethodHints: Qt.ImhNoPredictiveText
                focus: root.newMode
                Accessible.name: qsTr("Recipients")
                Accessible.description: qsTr("Enter one or more phone numbers")
            }

            Controls.Label {
                readonly property bool hasError: recipientsField.text.trim().length > 0 && root.hasInvalidRecipient()
                Layout.fillWidth: true
                opacity: hasError ? 1 : 0
                Accessible.ignored: !hasError
                text: qsTr("Enter valid phone numbers separated by commas or semicolons.")
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                font.pixelSize: 11
            }
        }

        ListView {
            id: messageList
            objectName: "messageList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.newMode
            Accessible.ignored: !visible
            model: root.messages
            clip: true
            spacing: Kirigami.Units.smallSpacing
            verticalLayoutDirection: ListView.TopToBottom
            topMargin: Kirigami.Units.largeSpacing
            bottomMargin: Kirigami.Units.largeSpacing
            leftMargin: Kirigami.Units.largeSpacing
            rightMargin: Kirigami.Units.largeSpacing
                + conversationScrollBar.implicitWidth
                + Kirigami.Units.smallSpacing

            function jumpToBottom() {
                if (!visible || count === 0)
                    return
                forceLayout()
                positionViewAtEnd()
            }

            onMovementEnded: root.followLatest = atYEnd
            onFlickEnded: root.followLatest = atYEnd
            onVisibleChanged: {
                if (visible && root.followLatest)
                    Qt.callLater(jumpToBottom)
            }

            Controls.ScrollBar.vertical: Controls.ScrollBar {
                id: conversationScrollBar
                policy: root.compactMode ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOn
                active: true
                Accessible.name: qsTr("Conversation scroll bar")
            }

            delegate: Item {
                required property var modelData
                required property int index
                readonly property bool showsDay: index === 0
                    || root.messageDayKey(modelData.timestamp) !== root.messageDayKey(root.messages[index - 1].timestamp)

                width: ListView.view.width - messageList.leftMargin - messageList.rightMargin
                height: bubble.implicitHeight + Kirigami.Units.smallSpacing + (showsDay ? 38 : 0)

                Controls.Label {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: parent.showsDay
                    text: root.messageDayLabel(modelData.timestamp)
                    color: Kirigami.Theme.textColor
                    opacity: 0.76
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                Rectangle {
                    id: bubble
                    anchors.top: parent.top
                    anchors.topMargin: parent.showsDay ? 28 : 0
                    anchors.right: modelData.outgoing ? parent.right : undefined
                    anchors.left: modelData.outgoing ? undefined : parent.left
                    width: Math.min(parent.width * 0.76, Math.max(108, messageContent.implicitWidth + Kirigami.Units.gridUnit * 2))
                    implicitHeight: messageContent.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: 16
                    color: modelData.outgoing
                        ? Kirigami.Theme.highlightColor
                        : root.translucent(Kirigami.Theme.textColor, 0.075)

                    ColumnLayout {
                        id: messageContent
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing
                        opacity: modelData.pending ? 0.7 : 1.0

                        Controls.Label {
                            Layout.fillWidth: true
                            visible: modelData.body.length > 0
                            text: modelData.body
                            color: modelData.outgoing ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            lineHeight: 1.12
                            font.pixelSize: 14
                        }

                        Repeater {
                            model: modelData.attachments

                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true

                                Controls.AbstractButton {
                                    id: imageAttachment

                                    Layout.preferredWidth: 180
                                    Layout.preferredHeight: visible ? 180 : 0
                                    Layout.alignment: modelData.outgoing ? Qt.AlignRight : Qt.AlignLeft
                                    visible: modelData.encoded_thumbnail.length > 0
                                        && modelData.mime_type.startsWith("image/")
                                    activeFocusOnTab: true
                                    Accessible.name: qsTr("Open image %1").arg(modelData.unique_identifier)
                                    onClicked: {
                                        root.setContextImage(
                                            thumbnailSource.source,
                                            modelData.unique_identifier,
                                            modelData.mime_type,
                                            modelData.part_id)
                                        root.openImagePreview(
                                            thumbnailSource.source,
                                            modelData.unique_identifier,
                                            modelData.part_id)
                                    }

                                    background: Rectangle {
                                        radius: 11
                                        color: root.translucent(Kirigami.Theme.textColor, 0.06)
                                        border.width: imageAttachment.activeFocus ? 2 : 1
                                        border.color: imageAttachment.activeFocus
                                            ? Kirigami.Theme.highlightColor
                                            : root.translucent(Kirigami.Theme.textColor, 0.12)
                                    }

                                    contentItem: Item {
                                        Image {
                                            id: thumbnailSource
                                            anchors.fill: parent
                                            visible: false
                                            source: root.downloadedImageSource
                                                    && root.downloadedImageName === root.attachmentKey(modelData.part_id, modelData.unique_identifier)
                                                ? root.downloadedImageSource
                                                : (imageAttachment.visible
                                                    ? "data:" + modelData.mime_type + ";base64," + modelData.encoded_thumbnail
                                                    : "")
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            smooth: true
                                            mipmap: true
                                        }

                                        Rectangle {
                                            id: thumbnailMask
                                            anchors.fill: parent
                                            visible: false
                                            radius: 10
                                            color: "white"
                                            layer.enabled: true
                                        }

                                        MultiEffect {
                                            anchors.fill: parent
                                            source: thumbnailSource
                                            maskEnabled: true
                                            maskSource: thumbnailMask
                                            maskThresholdMin: 0.5
                                            maskSpreadAtMin: 1.0
                                        }

                                        TapHandler {
                                            acceptedButtons: Qt.RightButton
                                            onTapped: root.showImageMenu(
                                                thumbnailSource.source,
                                                modelData.unique_identifier,
                                                modelData.mime_type,
                                                modelData.part_id)
                                        }

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 42
                                            color: root.translucent(Kirigami.Theme.backgroundColor, 0.88)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Kirigami.Units.largeSpacing
                                                anchors.rightMargin: Kirigami.Units.largeSpacing

                                                Kirigami.Icon {
                                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                                    source: "zoom-in"
                                                }

                                                Controls.Label {
                                                    Layout.fillWidth: true
                                                    text: qsTr("Open image")
                                                    font.weight: Font.Medium
                                                }
                                            }
                                        }
                                    }
                                }

                                Controls.Label {
                                    Layout.fillWidth: true
                                    visible: !modelData.mime_type.startsWith("image/")
                                        || modelData.encoded_thumbnail.length === 0
                                    text: modelData.unique_identifier
                                    color: bubble.color === Kirigami.Theme.highlightColor
                                        ? Kirigami.Theme.highlightedTextColor
                                        : Kirigami.Theme.textColor
                                    elide: Text.ElideMiddle
                                }
                            }
                        }

                        Controls.Button {
                            Layout.alignment: Qt.AlignRight
                            visible: modelData.failed
                            Accessible.ignored: !visible
                            text: qsTr("Edit and retry")
                            icon.name: "view-refresh"
                            flat: true
                            onClicked: root.editFailedMessage(modelData)
                        }

                        Controls.Label {
                            Layout.alignment: Qt.AlignRight
                            text: modelData.failed
                                ? qsTr("Not sent")
                                : (modelData.pending
                                    ? qsTr("Sending")
                                    : new Date(modelData.timestamp).toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
                            color: modelData.outgoing ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                            opacity: modelData.failed ? 1.0 : 0.82
                            font.pixelSize: 10
                            font.weight: modelData.failed ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                visible: messageList.count === 0 && !root.busy
                Accessible.ignored: !visible
                icon.name: "mail-message"
                text: qsTr("No messages in this thread")
                explanation: qsTr("Write below to start the conversation.")
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.newMode
            Accessible.ignored: !visible

            EmptyPane {
                anchors.centerIn: parent
                width: Math.min(parent.width, Kirigami.Units.gridUnit * 28)
                title: qsTr("Start with a number")
                description: qsTr("Add one or more recipients above, then write your message below. KDE Connect will send it through your phone.")
                actionText: ""
                actionIcon: "mail-message-new"
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: composerLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
            color: Kirigami.Theme.backgroundColor

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Kirigami.Theme.alternateBackgroundColor
            }

            ColumnLayout {
                id: composerLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    opacity: root.attachmentError.length > 0 ? 1 : 0
                    Accessible.ignored: root.attachmentError.length === 0
                    type: Kirigami.MessageType.Error
                    text: root.attachmentError.length > 0 ? root.attachmentError : " "
                    showCloseButton: false
                }

                Controls.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.attachments.length > 0 ? 38 : 0
                    visible: root.attachments.length > 0
                    Accessible.ignored: !visible

                    Row {
                        spacing: Kirigami.Units.smallSpacing

                        Repeater {
                            model: root.attachments

                            delegate: Controls.Button {
                                required property string modelData
                                required property int index
                                text: modelData.split("/").pop()
                                icon.name: "edit-delete-remove"
                                flat: true
                                onClicked: {
                                    const next = root.attachments.slice()
                                    next.splice(index, 1)
                                    root.attachments = next
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Controls.Button {
                        text: qsTr("Attach")
                        flat: true
                        enabled: !root.sending && root.phoneConnected
                        Accessible.name: root.phoneConnected
                            ? qsTr("Attach files")
                            : qsTr("Connect your phone to attach files")
                        onClicked: attachmentDialog.open()
                    }

                    Controls.TextArea {
                        id: messageField
                        objectName: "messageField"
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(104, Math.max(42, contentHeight + topPadding + bottomPadding))
                        Layout.maximumHeight: 104
                        placeholderText: root.newMode ? qsTr("Write a new message") : qsTr("Write a message")
                        wrapMode: TextEdit.Wrap
                        enabled: !root.sending
                        Accessible.name: qsTr("Message")
                        Accessible.description: qsTr("Press Control and Enter to send")
                        background: Rectangle {
                            radius: 10
                            color: root.translucent(Kirigami.Theme.textColor, 0.06)
                            border.width: messageField.activeFocus ? 2 : 1
                            border.color: messageField.activeFocus
                                ? Kirigami.Theme.highlightColor
                                : root.translucent(Kirigami.Theme.textColor, 0.12)
                        }

                        Keys.onPressed: event => {
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Return) {
                                root.submit()
                                event.accepted = true
                            }
                        }
                    }

                    Controls.Button {
                        icon.name: root.sending ? "view-refresh" : "document-send"
                        text: root.sending ? qsTr("Sending") : qsTr("Send")
                        Accessible.description: qsTr("Send message, Control and Enter")
                        enabled: root.phoneConnected
                            && !root.sending
                            && !root.sendPending
                            && (messageField.text.trim().length > 0 || root.attachments.length > 0)
                            && (!root.newMode
                                || (recipientsField.text.trim().length > 0 && !root.hasInvalidRecipient()))
                        onClicked: root.submit()
                    }
                }

                Controls.Label {
                    Layout.fillWidth: true
                    visible: root.connectionChecked && !root.phoneConnected
                    Accessible.ignored: !visible
                    text: qsTr("Connect your phone to send messages.")
                    color: Kirigami.Theme.textColor
                    opacity: 0.72
                    font.pixelSize: 11
                }
            }
        }

        Controls.ProgressBar {
            objectName: "activityProgress"
            Layout.fillWidth: true
            Layout.preferredHeight: 3
            opacity: root.busy || root.sending ? 1 : 0
            Accessible.ignored: !(root.busy || root.sending)
            Accessible.name: root.sending ? qsTr("Sending message") : qsTr("Refreshing messages")
            indeterminate: root.busy || root.sending
        }
    }
}
