use crate::cache::CachedState;
use crate::contacts::{infer_own_number, ContactBook};
use crate::kdeconnect::KdeConnectClient;
use crate::model::{Conversation, Device, UiMessage};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use std::pin::Pin;
use std::sync::mpsc::{self, Sender};

enum Command {
    Initialize,
    SelectDevice(String),
    RefreshConversations,
    OpenConversation(i64),
    RefreshMessages,
    HardResync,
    DownloadAttachment {
        part_id: i64,
        unique_identifier: String,
    },
    SendReply {
        text: String,
        attachments: Vec<String>,
        temporary_id: i32,
    },
    SendNew {
        addresses: Vec<String>,
        text: String,
        attachments: Vec<String>,
    },
}

enum Event {
    Devices(Vec<Device>),
    Conversations(Vec<Conversation>),
    Messages(Vec<UiMessage>),
    SelectedDevice(String),
    SelectedThread(i64),
    Busy(bool),
    Sending(bool),
    Error(String),
    Status(String),
    PhoneConnected(bool),
    ConnectionChecked(bool),
    AttachmentLoading(bool),
    AttachmentReady { source: String, name: String },
    MarkFailed(i32),
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        include!("sms2/src/qml_backend.h");
        type QString = cxx_qt_lib::QString;

        fn copy_image(data_url: &QString) -> bool;
        fn save_image(data_url: &QString, file_url: &QString) -> bool;
        fn register_sms2_backend();
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(QString, devices_json)]
        #[qproperty(QString, conversations_json)]
        #[qproperty(QString, messages_json)]
        #[qproperty(QString, selected_device)]
        #[qproperty(i64, selected_thread)]
        #[qproperty(bool, busy)]
        #[qproperty(bool, sending)]
        #[qproperty(QString, error_message)]
        #[qproperty(QString, status_message)]
        #[qproperty(bool, phone_connected)]
        #[qproperty(bool, connection_checked)]
        #[qproperty(bool, attachment_loading)]
        #[qproperty(QString, attachment_source)]
        #[qproperty(QString, attachment_name)]
        type AppController = super::AppControllerRust;

        #[qinvokable]
        fn initialize(self: Pin<&mut AppController>);

        #[qinvokable]
        fn select_device(self: Pin<&mut AppController>, device_id: QString);

        #[qinvokable]
        fn refresh_conversations(self: Pin<&mut AppController>);

        #[qinvokable]
        fn open_conversation(self: Pin<&mut AppController>, thread_id: i64);

        #[qinvokable]
        fn refresh_messages(self: Pin<&mut AppController>);

        #[qinvokable]
        fn hard_resync(self: Pin<&mut AppController>);

        #[qinvokable]
        fn download_attachment(
            self: Pin<&mut AppController>,
            part_id: i64,
            unique_identifier: QString,
        );

        #[qinvokable]
        fn send_reply(self: Pin<&mut AppController>, text: QString, attachments_json: QString);

        #[qinvokable]
        fn send_new(
            self: Pin<&mut AppController>,
            addresses_json: QString,
            text: QString,
            attachments_json: QString,
        );

        #[qinvokable]
        fn copy_image(self: Pin<&mut AppController>, data_url: QString) -> bool;

        #[qinvokable]
        fn save_image(self: Pin<&mut AppController>, data_url: QString, file_url: QString) -> bool;

        #[qinvokable]
        fn clear_error(self: Pin<&mut AppController>);
    }

    impl cxx_qt::Threading for AppController {}
}

pub struct AppControllerRust {
    devices_json: QString,
    conversations_json: QString,
    messages_json: QString,
    selected_device: QString,
    selected_thread: i64,
    busy: bool,
    sending: bool,
    error_message: QString,
    status_message: QString,
    phone_connected: bool,
    connection_checked: bool,
    attachment_loading: bool,
    attachment_source: QString,
    attachment_name: QString,
    command_tx: Option<Sender<Command>>,
}

impl Default for AppControllerRust {
    fn default() -> Self {
        Self {
            devices_json: QString::from("[]"),
            conversations_json: QString::from("[]"),
            messages_json: QString::from("[]"),
            selected_device: QString::default(),
            selected_thread: -1,
            busy: false,
            sending: false,
            error_message: QString::default(),
            status_message: QString::from("Connecting to KDE Connect"),
            phone_connected: false,
            connection_checked: false,
            attachment_loading: false,
            attachment_source: QString::default(),
            attachment_name: QString::default(),
            command_tx: None,
        }
    }
}

impl ffi::AppController {
    pub fn initialize(mut self: Pin<&mut Self>) {
        if self.command_tx.is_some() {
            return;
        }

        let (tx, rx) = mpsc::channel();
        self.as_mut().rust_mut().command_tx = Some(tx.clone());
        let cached = CachedState::load();
        if let Some(device) = cached.device.clone() {
            self.as_mut().set_selected_device(QString::from(&device.id));
            self.as_mut().set_devices_json(to_json(&vec![device]));
        }

        let initial_thread_id = cached
            .conversations
            .iter()
            .max_by_key(|conversation| conversation.timestamp)
            .map(|conversation| conversation.thread_id)
            .unwrap_or(-1);
        if !cached.conversations.is_empty() {
            self.as_mut()
                .set_conversations_json(to_json(&cached.conversations));
            self.as_mut().set_selected_thread(initial_thread_id);
            if let Some(messages) = cached.messages.get(&initial_thread_id) {
                self.as_mut().set_messages_json(to_json(messages));
            }
            self.as_mut()
                .set_status_message(QString::from("Showing cached messages"));
        }
        let qt_thread = self.qt_thread();

        std::thread::spawn(move || {
            let runtime = match tokio::runtime::Runtime::new() {
                Ok(runtime) => runtime,
                Err(error) => {
                    queue_event(
                        &qt_thread,
                        Event::Error(format!("Could not start the messaging service: {error}")),
                    );
                    return;
                }
            };

            runtime.block_on(async move {
                let client = match KdeConnectClient::connect().await {
                    Ok(client) => client,
                    Err(error) => {
                        queue_event(
                            &qt_thread,
                            Event::Error(format!("Could not connect to KDE Connect: {error}")),
                        );
                        return;
                    }
                };

                let mut cache = cached;
                let mut device_id = cache
                    .device
                    .as_ref()
                    .map(|device| device.id.clone())
                    .unwrap_or_default();
                let mut thread_id = initial_thread_id;
                let mut contacts = ContactBook::default();
                let session_started_at = unix_millis();

                while let Ok(command) = rx.recv() {
                    queue_event(&qt_thread, Event::Error(String::new()));
                    let result = match command {
                        Command::Initialize => {
                            refresh_devices(
                                &client,
                                &qt_thread,
                                &mut device_id,
                                &mut thread_id,
                                &mut contacts,
                                &mut cache,
                                session_started_at,
                            )
                            .await
                        }
                        Command::SelectDevice(id) => {
                            device_id = id;
                            thread_id = -1;
                            queue_event(&qt_thread, Event::SelectedDevice(device_id.clone()));
                            queue_event(&qt_thread, Event::SelectedThread(-1));
                            queue_event(&qt_thread, Event::Conversations(vec![]));
                            queue_event(&qt_thread, Event::Messages(vec![]));
                            load_conversations(
                                &client,
                                &qt_thread,
                                &device_id,
                                &mut contacts,
                                &mut cache,
                                session_started_at,
                            )
                            .await
                        }
                        Command::RefreshConversations => {
                            refresh_devices(
                                &client,
                                &qt_thread,
                                &mut device_id,
                                &mut thread_id,
                                &mut contacts,
                                &mut cache,
                                session_started_at,
                            )
                            .await
                        }
                        Command::OpenConversation(id) => {
                            thread_id = id;
                            queue_event(&qt_thread, Event::SelectedThread(id));
                            if id < 0 {
                                queue_event(&qt_thread, Event::Messages(vec![]));
                                Ok(())
                            } else {
                                if let Some(messages) = cache.messages.get(&id) {
                                    queue_event(&qt_thread, Event::Messages(messages.clone()));
                                }
                                load_messages(
                                    &client, &qt_thread, &device_id, thread_id, &mut cache,
                                )
                                .await
                            }
                        }
                        Command::RefreshMessages if !device_id.is_empty() && thread_id >= 0 => {
                            load_messages(&client, &qt_thread, &device_id, thread_id, &mut cache)
                                .await
                        }
                        Command::HardResync => {
                            let result = refresh_devices(
                                &client,
                                &qt_thread,
                                &mut device_id,
                                &mut thread_id,
                                &mut contacts,
                                &mut cache,
                                session_started_at,
                            )
                            .await;
                            if result.is_ok() && !device_id.is_empty() && thread_id >= 0 {
                                load_messages(
                                    &client, &qt_thread, &device_id, thread_id, &mut cache,
                                )
                                .await
                            } else {
                                result
                            }
                        }
                        Command::DownloadAttachment {
                            part_id,
                            unique_identifier,
                        } => {
                            if device_id.is_empty() {
                                Err("Connect the phone to open the full image".into())
                            } else {
                                queue_event(&qt_thread, Event::AttachmentLoading(true));
                                match client
                                    .download_attachment(&device_id, part_id, &unique_identifier)
                                    .await
                                {
                                    Ok(path) => {
                                        queue_event(
                                            &qt_thread,
                                            Event::AttachmentReady {
                                                source: path,
                                                name: unique_identifier,
                                            },
                                        );
                                        queue_event(&qt_thread, Event::AttachmentLoading(false));
                                        Ok(())
                                    }
                                    Err(error) => {
                                        queue_event(&qt_thread, Event::AttachmentLoading(false));
                                        Err(error)
                                    }
                                }
                            }
                        }
                        Command::SendReply {
                            text,
                            attachments,
                            temporary_id,
                        } => {
                            if device_id.is_empty() || thread_id < 0 {
                                Err("Choose a conversation before sending a message".into())
                            } else if text.trim().is_empty() && attachments.is_empty() {
                                Err("Write a message or attach a file before sending".into())
                            } else {
                                cache
                                    .messages
                                    .entry(thread_id)
                                    .or_default()
                                    .push(UiMessage {
                                        id: temporary_id,
                                        thread_id,
                                        body: text.clone(),
                                        timestamp: unix_millis(),
                                        outgoing: true,
                                        sender: String::new(),
                                        attachments: Vec::new(),
                                        pending: true,
                                        failed: false,
                                    });
                                let _ = cache.save();
                                queue_event(&qt_thread, Event::Sending(true));
                                let result = client
                                    .send_reply(&device_id, thread_id, &text, attachments)
                                    .await;
                                let result = if result.is_ok() {
                                    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                                    load_messages(
                                        &client, &qt_thread, &device_id, thread_id, &mut cache,
                                    )
                                    .await
                                } else {
                                    result
                                };
                                finish_send(&qt_thread, result, Some(temporary_id))
                            }
                        }
                        Command::SendNew {
                            addresses,
                            text,
                            attachments,
                        } => {
                            if device_id.is_empty() {
                                Err("Connect a phone before sending a message".into())
                            } else if addresses.is_empty() {
                                Err("Add at least one recipient before sending".into())
                            } else if text.trim().is_empty() && attachments.is_empty() {
                                Err("Write a message or attach a file before sending".into())
                            } else {
                                queue_event(&qt_thread, Event::Sending(true));
                                let result = client
                                    .send_new(&device_id, addresses, &text, attachments)
                                    .await;
                                let result = if result.is_ok() {
                                    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                                    load_conversations(
                                        &client,
                                        &qt_thread,
                                        &device_id,
                                        &mut contacts,
                                        &mut cache,
                                        session_started_at,
                                    )
                                    .await
                                } else {
                                    result
                                };
                                finish_send(&qt_thread, result, None)
                            }
                        }
                        _ => Ok(()),
                    };

                    queue_event(&qt_thread, Event::Busy(false));
                    if let Err(error) = result {
                        queue_event(&qt_thread, Event::Status("Connection problem".into()));
                        queue_event(&qt_thread, Event::Error(error.to_string()));
                    }
                }
            });
        });

        let _ = tx.send(Command::Initialize);
    }

    pub fn select_device(self: Pin<&mut Self>, device_id: QString) {
        self.send(Command::SelectDevice(device_id.to_string()));
    }

    pub fn refresh_conversations(self: Pin<&mut Self>) {
        self.send(Command::RefreshConversations);
    }

    pub fn open_conversation(mut self: Pin<&mut Self>, thread_id: i64) {
        self.as_mut().set_selected_thread(thread_id);
        if thread_id < 0 {
            self.as_mut().set_messages_json(QString::from("[]"));
        } else {
            let cached = CachedState::load();
            let messages = cached.messages.get(&thread_id).cloned().unwrap_or_default();
            self.as_mut().set_messages_json(to_json(&messages));
        }
        self.send(Command::OpenConversation(thread_id));
    }

    pub fn refresh_messages(self: Pin<&mut Self>) {
        self.send(Command::RefreshMessages);
    }

    pub fn hard_resync(self: Pin<&mut Self>) {
        self.send(Command::HardResync);
    }

    pub fn download_attachment(mut self: Pin<&mut Self>, part_id: i64, unique_identifier: QString) {
        self.as_mut().set_attachment_source(QString::default());
        self.send(Command::DownloadAttachment {
            part_id,
            unique_identifier: unique_identifier.to_string(),
        });
    }

    pub fn send_reply(mut self: Pin<&mut Self>, text: QString, attachments_json: QString) {
        let attachments = parse_string_list(&attachments_json.to_string());
        let temporary_id = next_temporary_id();
        let mut messages: Vec<UiMessage> =
            serde_json::from_str(&self.messages_json.to_string()).unwrap_or_default();
        messages.push(UiMessage {
            id: temporary_id,
            thread_id: self.selected_thread,
            body: text.to_string(),
            timestamp: unix_millis(),
            outgoing: true,
            sender: String::new(),
            attachments: attachments
                .iter()
                .enumerate()
                .map(|(index, path)| crate::model::Attachment {
                    part_id: -(index as i64) - 1,
                    mime_type: String::new(),
                    encoded_thumbnail: String::new(),
                    unique_identifier: path.clone(),
                })
                .collect(),
            pending: true,
            failed: false,
        });
        self.as_mut().set_messages_json(to_json(&messages));
        self.send(Command::SendReply {
            text: text.to_string(),
            attachments,
            temporary_id,
        });
    }

    pub fn send_new(
        self: Pin<&mut Self>,
        addresses_json: QString,
        text: QString,
        attachments_json: QString,
    ) {
        self.send(Command::SendNew {
            addresses: parse_string_list(&addresses_json.to_string()),
            text: text.to_string(),
            attachments: parse_string_list(&attachments_json.to_string()),
        });
    }

    pub fn copy_image(self: Pin<&mut Self>, data_url: QString) -> bool {
        ffi::copy_image(&data_url)
    }

    pub fn save_image(self: Pin<&mut Self>, data_url: QString, file_url: QString) -> bool {
        ffi::save_image(&data_url, &file_url)
    }

    pub fn clear_error(mut self: Pin<&mut Self>) {
        self.as_mut().set_error_message(QString::default());
    }

    fn send(&self, command: Command) {
        if let Some(tx) = &self.command_tx {
            let _ = tx.send(command);
        }
    }
}

async fn refresh_devices(
    client: &KdeConnectClient,
    qt_thread: &cxx_qt::CxxQtThread<ffi::AppController>,
    device_id: &mut String,
    thread_id: &mut i64,
    contacts: &mut ContactBook,
    cache: &mut CachedState,
    notifications_since: i64,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    queue_event(qt_thread, Event::Busy(true));
    queue_event(qt_thread, Event::Status("Looking for phones".into()));
    let devices = match client.devices().await {
        Ok(devices) => devices,
        Err(error) => {
            queue_event(qt_thread, Event::PhoneConnected(false));
            queue_event(qt_thread, Event::ConnectionChecked(true));
            return Err(error);
        }
    };

    if !devices.iter().any(|device| device.id == *device_id) {
        *device_id = devices
            .first()
            .map(|device| device.id.clone())
            .unwrap_or_default();
        *thread_id = -1;
        queue_event(qt_thread, Event::SelectedDevice(device_id.clone()));
        queue_event(qt_thread, Event::SelectedThread(-1));
        queue_event(qt_thread, Event::Messages(vec![]));
    }

    let phone_connected = devices
        .iter()
        .any(|device| device.id == *device_id && device.reachable);
    queue_event(qt_thread, Event::PhoneConnected(phone_connected));
    queue_event(qt_thread, Event::ConnectionChecked(true));

    cache.device = devices
        .iter()
        .find(|device| device.id == *device_id)
        .cloned();
    let _ = cache.save();
    queue_event(qt_thread, Event::Devices(devices));
    if device_id.is_empty() {
        queue_event(qt_thread, Event::Conversations(vec![]));
        queue_event(
            qt_thread,
            Event::Status("No reachable phone with SMS support".into()),
        );
        Ok(())
    } else {
        load_conversations(
            client,
            qt_thread,
            device_id,
            contacts,
            cache,
            notifications_since,
        )
        .await
    }
}

fn finish_send(
    qt_thread: &cxx_qt::CxxQtThread<ffi::AppController>,
    result: Result<(), Box<dyn std::error::Error + Send + Sync>>,
    temporary_id: Option<i32>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    if let Err(error) = result {
        if let Some(id) = temporary_id {
            queue_event(qt_thread, Event::MarkFailed(id));
        }
        queue_event(qt_thread, Event::Status("Message not sent".into()));
        queue_event(qt_thread, Event::Error(error.to_string()));
    }
    queue_event(qt_thread, Event::Sending(false));
    Ok(())
}

async fn load_conversations(
    client: &KdeConnectClient,
    qt_thread: &cxx_qt::CxxQtThread<ffi::AppController>,
    device_id: &str,
    contacts: &mut ContactBook,
    cache: &mut CachedState,
    notifications_since: i64,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    queue_event(qt_thread, Event::Busy(true));
    queue_event(
        qt_thread,
        Event::Status("Syncing conversations and contacts".into()),
    );
    let _ = client.synchronize_contacts(device_id).await;
    *contacts = ContactBook::load(device_id);
    let mut conversations = client.request_conversations(device_id).await?;
    cache.own_number = infer_own_number(&conversations, cache.own_number.as_deref());
    contacts.decorate(&mut conversations, cache.own_number.as_deref());

    if !cache.conversations.is_empty() {
        for conversation in &conversations {
            let previous_timestamp = cache
                .conversations
                .iter()
                .find(|cached| cached.thread_id == conversation.thread_id)
                .map(|cached| cached.timestamp)
                .unwrap_or_default();
            if !conversation.outgoing
                && conversation.timestamp >= notifications_since
                && conversation.timestamp > previous_timestamp
            {
                let _ = client
                    .show_notification(&conversation.title, &conversation.preview)
                    .await;
            }
        }
    }

    cache.conversations = conversations.clone();
    let _ = cache.save();
    cache_all_threads_in_background(
        device_id.to_owned(),
        conversations.iter().map(|item| item.thread_id).collect(),
    );
    queue_event(qt_thread, Event::Conversations(conversations));
    queue_event(qt_thread, Event::Status("Up to date".into()));
    Ok(())
}

async fn load_messages(
    client: &KdeConnectClient,
    qt_thread: &cxx_qt::CxxQtThread<ffi::AppController>,
    device_id: &str,
    thread_id: i64,
    cache: &mut CachedState,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    queue_event(qt_thread, Event::Busy(true));
    queue_event(qt_thread, Event::Status("Syncing messages".into()));
    let mut messages = client.messages(device_id, thread_id).await?;
    if let Some(cached) = cache.messages.get(&thread_id) {
        for pending in cached
            .iter()
            .filter(|message| message.pending || message.failed)
        {
            let confirmed = messages.iter().any(|message| {
                message.outgoing
                    && message.body == pending.body
                    && (message.timestamp - pending.timestamp).abs() < 120_000
            });
            if !confirmed {
                messages.push(pending.clone());
            }
        }
    }
    messages.sort_by_key(|message| message.timestamp);
    cache.messages.insert(thread_id, messages.clone());
    let _ = cache.save();
    queue_event(qt_thread, Event::Messages(messages));
    queue_event(qt_thread, Event::Status("Up to date".into()));
    Ok(())
}

fn cache_all_threads_in_background(device_id: String, thread_ids: Vec<i64>) {
    use std::sync::atomic::{AtomicBool, Ordering};
    static RUNNING: AtomicBool = AtomicBool::new(false);
    if RUNNING.swap(true, Ordering::AcqRel) {
        return;
    }
    std::thread::spawn(move || {
        if let Ok(runtime) = tokio::runtime::Runtime::new() {
            runtime.block_on(async move {
                if let Ok(client) = KdeConnectClient::connect().await {
                    for thread_id in thread_ids {
                        let current = CachedState::load();
                        if current
                            .messages
                            .get(&thread_id)
                            .is_some_and(|messages| !messages.is_empty())
                        {
                            continue;
                        }
                        if let Ok(messages) = client.messages(&device_id, thread_id).await {
                            let mut latest = CachedState::load();
                            latest.messages.insert(thread_id, messages);
                            let _ = latest.save();
                        }
                    }
                }
            });
        }
        RUNNING.store(false, Ordering::Release);
    });
}

fn queue_event(thread: &cxx_qt::CxxQtThread<ffi::AppController>, event: Event) {
    let _ = thread.queue(move |mut controller| match event {
        Event::Devices(value) => controller.as_mut().set_devices_json(to_json(&value)),
        Event::Conversations(value) => controller.as_mut().set_conversations_json(to_json(&value)),
        Event::Messages(value) => controller.as_mut().set_messages_json(to_json(&value)),
        Event::SelectedDevice(value) => controller
            .as_mut()
            .set_selected_device(QString::from(&value)),
        Event::SelectedThread(value) => controller.as_mut().set_selected_thread(value),
        Event::Busy(value) => controller.as_mut().set_busy(value),
        Event::Sending(value) => controller.as_mut().set_sending(value),
        Event::Error(value) => controller.as_mut().set_error_message(QString::from(&value)),
        Event::Status(value) => controller
            .as_mut()
            .set_status_message(QString::from(&value)),
        Event::PhoneConnected(value) => controller.as_mut().set_phone_connected(value),
        Event::ConnectionChecked(value) => controller.as_mut().set_connection_checked(value),
        Event::AttachmentLoading(value) => controller.as_mut().set_attachment_loading(value),
        Event::AttachmentReady { source, name } => {
            controller
                .as_mut()
                .set_attachment_name(QString::from(&name));
            controller
                .as_mut()
                .set_attachment_source(QString::from(&format!("file://{source}")));
        }
        Event::MarkFailed(id) => {
            let mut messages: Vec<UiMessage> =
                serde_json::from_str(&controller.messages_json.to_string()).unwrap_or_default();
            if let Some(message) = messages.iter_mut().find(|message| message.id == id) {
                message.pending = false;
                message.failed = true;
            }
            controller.as_mut().set_messages_json(to_json(&messages));
        }
    });
}

fn to_json<T: serde::Serialize>(value: &T) -> QString {
    QString::from(serde_json::to_string(value).unwrap_or_else(|_| "[]".into()))
}

fn parse_string_list(json: &str) -> Vec<String> {
    serde_json::from_str(json).unwrap_or_default()
}

fn unix_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn next_temporary_id() -> i32 {
    use std::sync::atomic::{AtomicI32, Ordering};
    static NEXT: AtomicI32 = AtomicI32::new(-1);
    NEXT.fetch_sub(1, Ordering::Relaxed)
}
