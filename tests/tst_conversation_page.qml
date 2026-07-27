import QtQuick
import QtQuick.Window
import QtTest
import "../src/qml" as Sms2

TestCase {
    id: testCase
    name: "ConversationPage"
    when: testWindow.visible

    Window {
        id: testWindow
        width: 900
        height: 700
        visible: true

        Sms2.ConversationPage {
            id: page
            anchors.fill: parent
            visible: true
            phoneConnected: true
            connectionChecked: true
        }
    }

    function init() {
        page.newMode = false
        page.conversation = ({ threadId: 1, title: "One", participants: ["+10000000001"], avatar: "" })
        page.messages = []
        const field = findChild(page, "messageField")
        field.clear()
        page.attachments = []
    }

    function test_recipient_validation() {
        verify(page.recipientIsValid("+61 412 345 678"))
        verify(page.recipientIsValid("555-123-456"))
        verify(!page.recipientIsValid("not-a-number"))
    }

    function test_compose_focuses_recipients() {
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
        page.forceActiveFocus()
        page.newMode = true
        tryCompare(findChild(page, "recipientsField"), "activeFocus", true)
    }

    function test_reply_drafts_are_isolated_by_thread() {
        const field = findChild(page, "messageField")
        field.text = "draft for one"
        page.attachments = ["/tmp/one.jpg"]

        page.conversation = ({ threadId: 2, title: "Two", participants: ["+10000000002"], avatar: "" })
        compare(field.text, "")
        compare(page.attachments.length, 0)
        field.text = "draft for two"
        page.attachments = ["/tmp/two.jpg"]

        page.conversation = ({ threadId: 1, title: "One", participants: ["+10000000001"], avatar: "" })
        compare(field.text, "draft for one")
        compare(page.attachments[0], "/tmp/one.jpg")
    }

    function test_refresh_state_does_not_resize_the_message_view() {
        const list = findChild(page, "messageList")
        const progress = findChild(page, "activityProgress")
        const initialHeight = list.height
        const initialProgressHeight = progress.height

        page.busy = true
        wait(0)
        compare(list.height, initialHeight)
        compare(progress.height, initialProgressHeight)

        page.busy = false
        wait(0)
        compare(list.height, initialHeight)
        compare(progress.height, initialProgressHeight)
    }

    function test_attachment_keys_include_thread_and_part() {
        compare(page.attachmentKey(7, "image.jpg"), "1:7:image.jpg")
        page.conversation = ({ threadId: 2, title: "Two", participants: ["+10000000002"], avatar: "" })
        compare(page.attachmentKey(7, "image.jpg"), "2:7:image.jpg")
    }
}
