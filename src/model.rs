use serde::{Deserialize, Serialize};
use zvariant::Type;

#[derive(Clone, Debug, Deserialize, Serialize, Type)]
pub struct Address {
    pub address: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, Type)]
pub struct Attachment {
    pub part_id: i64,
    pub mime_type: String,
    pub encoded_thumbnail: String,
    pub unique_identifier: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, Type)]
pub struct Message {
    pub event: i32,
    pub body: String,
    pub addresses: Vec<Address>,
    pub date: i64,
    pub message_type: i32,
    pub read: i32,
    pub thread_id: i64,
    pub id: i32,
    pub subscription_id: i64,
    pub attachments: Vec<Attachment>,
}

impl Message {
    pub fn is_outgoing(&self) -> bool {
        matches!(self.message_type, 2..=6)
    }

    pub fn participants(&self) -> Vec<String> {
        self.addresses
            .iter()
            .map(|item| item.address.clone())
            .collect()
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Device {
    pub id: String,
    pub name: String,
    pub reachable: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Conversation {
    pub thread_id: i64,
    pub title: String,
    pub preview: String,
    pub timestamp: i64,
    pub outgoing: bool,
    pub participants: Vec<String>,
    pub has_attachment: bool,
    #[serde(default)]
    pub avatar: String,
}

impl From<&Message> for Conversation {
    fn from(message: &Message) -> Self {
        let participants = message.participants();
        let title = if participants.is_empty() {
            "Unknown conversation".to_owned()
        } else {
            participants.join(", ")
        };
        let preview = if !message.body.trim().is_empty() {
            message.body.replace('\n', " ")
        } else if !message.attachments.is_empty() {
            "Attachment".to_owned()
        } else {
            "No message text".to_owned()
        };

        Self {
            thread_id: message.thread_id,
            title,
            preview,
            timestamp: message.date,
            outgoing: message.is_outgoing(),
            participants,
            has_attachment: !message.attachments.is_empty(),
            avatar: String::new(),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UiMessage {
    pub id: i32,
    pub thread_id: i64,
    pub body: String,
    pub timestamp: i64,
    pub outgoing: bool,
    pub sender: String,
    pub attachments: Vec<Attachment>,
    #[serde(default)]
    pub pending: bool,
    #[serde(default)]
    pub failed: bool,
}

impl From<Message> for UiMessage {
    fn from(message: Message) -> Self {
        let outgoing = message.is_outgoing();
        Self {
            id: message.id,
            thread_id: message.thread_id,
            body: message.body,
            timestamp: message.date,
            outgoing,
            sender: message
                .addresses
                .first()
                .map(|address| address.address.clone())
                .unwrap_or_default(),
            attachments: message.attachments,
            pending: false,
            failed: false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message(message_type: i32) -> Message {
        Message {
            event: 1,
            body: "A message\nwith a second line".into(),
            addresses: vec![Address {
                address: "+15551234".into(),
            }],
            date: 1_721_234_567_890,
            message_type,
            read: 1,
            thread_id: 42,
            id: 8,
            subscription_id: -1,
            attachments: vec![],
        }
    }

    #[test]
    fn identifies_message_direction() {
        assert!(!message(1).is_outgoing());
        assert!(message(2).is_outgoing());
        assert!(message(6).is_outgoing());
    }

    #[test]
    fn creates_compact_conversation_preview() {
        let conversation = Conversation::from(&message(1));
        assert_eq!(conversation.title, "+15551234");
        assert_eq!(conversation.preview, "A message with a second line");
    }
}
