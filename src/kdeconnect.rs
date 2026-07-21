use crate::model::{Address, Attachment, Conversation, Device, Message, UiMessage};
use futures_util::StreamExt;
use std::collections::HashMap;
use std::error::Error;
use std::time::Duration;
use zbus::{Connection, Proxy};
use zvariant::{OwnedValue, Type, Value};

const SERVICE: &str = "org.kde.kdeconnect";
const DAEMON_PATH: &str = "/modules/kdeconnect";
const DAEMON_INTERFACE: &str = "org.kde.kdeconnect.daemon";
const DEVICE_INTERFACE: &str = "org.kde.kdeconnect.device";
const CONVERSATIONS_INTERFACE: &str = "org.kde.kdeconnect.device.conversations";
const CONTACTS_INTERFACE: &str = "org.kde.kdeconnect.device.contacts";
const NOTIFICATIONS_SERVICE: &str = "org.freedesktop.Notifications";
const NOTIFICATIONS_PATH: &str = "/org/freedesktop/Notifications";
const NOTIFICATIONS_INTERFACE: &str = "org.freedesktop.Notifications";

type Result<T> = std::result::Result<T, Box<dyn Error + Send + Sync>>;
type AddressWire = (String,);
type AttachmentWire = (i64, String, String, String);
type MessageWire = (
    i32,
    String,
    Vec<AddressWire>,
    i64,
    i32,
    i32,
    i64,
    i32,
    i64,
    Vec<AttachmentWire>,
);

pub struct KdeConnectClient {
    connection: Connection,
}

impl KdeConnectClient {
    pub async fn connect() -> Result<Self> {
        Ok(Self {
            connection: Connection::session().await?,
        })
    }

    pub async fn devices(&self) -> Result<Vec<Device>> {
        let daemon = Proxy::new(&self.connection, SERVICE, DAEMON_PATH, DAEMON_INTERFACE).await?;
        let ids: Vec<String> = daemon.call("devices", &(true, true)).await?;
        let mut devices = Vec::new();

        for id in ids {
            let path = device_path(&id);
            let proxy = Proxy::new(&self.connection, SERVICE, path, DEVICE_INTERFACE).await?;
            let plugins: Vec<String> = proxy.call("loadedPlugins", &()).await?;
            if !plugins.iter().any(|plugin| plugin == "kdeconnect_sms") {
                continue;
            }

            devices.push(Device {
                id,
                name: proxy
                    .get_property("name")
                    .await
                    .unwrap_or_else(|_| "Phone".into()),
                reachable: proxy.get_property("isReachable").await.unwrap_or(true),
            });
        }

        Ok(devices)
    }

    pub async fn request_conversations(&self, device_id: &str) -> Result<Vec<Conversation>> {
        let proxy = self.conversations_proxy(device_id).await?;
        proxy
            .call::<_, _, ()>("requestAllConversationThreads", &())
            .await?;
        tokio::time::sleep(Duration::from_millis(900)).await;
        let values: Vec<OwnedValue> = proxy.call("activeConversations", &()).await?;
        let mut conversations: Vec<_> = values
            .into_iter()
            .map(decode_message)
            .collect::<Result<Vec<_>>>()?
            .iter()
            .map(Conversation::from)
            .collect();
        conversations.sort_by(|left, right| right.timestamp.cmp(&left.timestamp));
        Ok(conversations)
    }

    pub async fn messages(&self, device_id: &str, thread_id: i64) -> Result<Vec<UiMessage>> {
        let proxy = self.conversations_proxy(device_id).await?;
        let mut updates = proxy.receive_signal("conversationUpdated").await?;
        let mut loaded = proxy.receive_signal("conversationLoaded").await?;
        proxy
            .call::<_, _, ()>("requestConversation", &(thread_id, 0_i32, 5_000_i32))
            .await?;

        let mut messages = Vec::new();
        let collect = async {
            loop {
                tokio::select! {
                    update = updates.next() => {
                        let Some(update) = update else { break };
                        let (value,): (OwnedValue,) = update.body().deserialize()?;
                        let message = decode_message(value)?;
                        if message.thread_id == thread_id {
                            messages.push(UiMessage::from(message));
                        }
                    }
                    completion = loaded.next() => {
                        let Some(completion) = completion else { break };
                        let (loaded_thread, _count): (i64, u64) = completion.body().deserialize()?;
                        if loaded_thread == thread_id {
                            break;
                        }
                    }
                }
            }
            Ok::<(), Box<dyn Error + Send + Sync>>(())
        };

        match tokio::time::timeout(Duration::from_secs(4), collect).await {
            Ok(result) => result?,
            Err(_) if messages.is_empty() => {
                return Err("The phone did not return messages in time".into());
            }
            Err(_) => {}
        }

        messages.sort_by_key(|message| message.timestamp);
        messages.dedup_by_key(|message| message.id);
        Ok(messages)
    }

    pub async fn show_notification(&self, title: &str, body: &str) -> Result<()> {
        let proxy = Proxy::new(
            &self.connection,
            NOTIFICATIONS_SERVICE,
            NOTIFICATIONS_PATH,
            NOTIFICATIONS_INTERFACE,
        )
        .await?;
        let _: u32 = proxy
            .call(
                "Notify",
                &(
                    "SMS2",
                    0_u32,
                    "org.kde.sms2",
                    title,
                    body,
                    Vec::<String>::new(),
                    HashMap::<String, OwnedValue>::new(),
                    5000_i32,
                ),
            )
            .await?;
        Ok(())
    }

    pub async fn synchronize_contacts(&self, device_id: &str) -> Result<()> {
        let proxy = Proxy::new(
            &self.connection,
            SERVICE,
            format!("{}/contacts", device_path(device_id)),
            CONTACTS_INTERFACE,
        )
        .await?;
        proxy
            .call::<_, _, ()>("synchronizeRemoteWithLocal", &())
            .await?;
        tokio::time::sleep(Duration::from_millis(700)).await;
        Ok(())
    }

    pub async fn download_attachment(
        &self,
        device_id: &str,
        part_id: i64,
        unique_identifier: &str,
    ) -> Result<String> {
        let proxy = self.conversations_proxy(device_id).await?;
        let mut received = proxy.receive_signal("attachmentReceived").await?;
        proxy
            .call::<_, _, ()>("requestAttachmentFile", &(part_id, unique_identifier))
            .await?;

        let wait_for_file = async {
            while let Some(signal) = received.next().await {
                let (file_path, file_name): (String, String) = signal.body().deserialize()?;
                if file_name == unique_identifier {
                    return Ok(file_path);
                }
            }
            Err("KDE Connect stopped waiting for the image".into())
        };

        tokio::time::timeout(Duration::from_secs(20), wait_for_file)
            .await
            .map_err(|_| "The phone did not return the full image in time")?
    }

    pub async fn send_reply(
        &self,
        device_id: &str,
        thread_id: i64,
        text: &str,
        attachments: Vec<String>,
    ) -> Result<()> {
        let proxy = self.conversations_proxy(device_id).await?;
        let files = variants(attachments)?;
        proxy
            .call::<_, _, ()>("replyToConversation", &(thread_id, text, files))
            .await?;
        Ok(())
    }

    pub async fn send_new(
        &self,
        device_id: &str,
        addresses: Vec<String>,
        text: &str,
        attachments: Vec<String>,
    ) -> Result<()> {
        let proxy = self.conversations_proxy(device_id).await?;
        let addresses = addresses
            .into_iter()
            .map(|address| owned_variant((address,)))
            .collect::<Result<Vec<_>>>()?;
        let files = variants(attachments)?;
        proxy
            .call::<_, _, ()>("sendWithoutConversation", &(addresses, text, files))
            .await?;
        Ok(())
    }

    async fn conversations_proxy(&self, device_id: &str) -> Result<Proxy<'_>> {
        Ok(Proxy::new(
            &self.connection,
            SERVICE,
            device_path(device_id),
            CONVERSATIONS_INTERFACE,
        )
        .await?)
    }
}

fn device_path(device_id: &str) -> String {
    format!("/modules/kdeconnect/devices/{device_id}")
}

fn decode_message(value: OwnedValue) -> Result<Message> {
    let wire: MessageWire = value.try_into()?;
    Ok(Message {
        event: wire.0,
        body: wire.1,
        addresses: wire
            .2
            .into_iter()
            .map(|address| Address { address: address.0 })
            .collect(),
        date: wire.3,
        message_type: wire.4,
        read: wire.5,
        thread_id: wire.6,
        id: wire.7,
        subscription_id: wire.8,
        attachments: wire
            .9
            .into_iter()
            .map(|item| Attachment {
                part_id: item.0,
                mime_type: item.1,
                encoded_thumbnail: item.2,
                unique_identifier: item.3,
            })
            .collect(),
    })
}

fn owned_variant<T>(value: T) -> Result<OwnedValue>
where
    T: Type + Into<Value<'static>>,
{
    Ok(Value::new(value).try_to_owned()?)
}

fn variants(values: Vec<String>) -> Result<Vec<OwnedValue>> {
    values.into_iter().map(owned_variant).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_object_path_is_stable() {
        assert_eq!(device_path("abc"), "/modules/kdeconnect/devices/abc");
    }

    #[test]
    fn message_signature_matches_kde_connect() {
        assert_eq!(MessageWire::SIGNATURE.to_string(), "(isa(s)xiixixa(xsss))");
    }
}
