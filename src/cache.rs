use crate::model::{Conversation, Device, UiMessage};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::fs::OpenOptions;
use std::io;
use std::io::Write;
#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct CachedState {
    pub device: Option<Device>,
    pub conversations: Vec<Conversation>,
    pub messages: HashMap<i64, Vec<UiMessage>>,
    pub own_number: Option<String>,
    pub updated_at: i64,
}

impl CachedState {
    pub fn load() -> Self {
        cache_file()
            .and_then(|path| fs::read(path).ok())
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default()
    }

    pub fn save(&mut self) -> io::Result<()> {
        let Some(path) = cache_file() else {
            return Ok(());
        };
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        self.updated_at = unix_millis();
        use std::sync::atomic::{AtomicU64, Ordering};
        static NEXT_FILE: AtomicU64 = AtomicU64::new(1);
        let temporary =
            path.with_extension(format!("{}.tmp", NEXT_FILE.fetch_add(1, Ordering::Relaxed)));
        let bytes = serde_json::to_vec(self).map_err(io::Error::other)?;
        let mut options = OpenOptions::new();
        options.create_new(true).write(true);
        #[cfg(unix)]
        options.mode(0o600);
        let mut file = options.open(&temporary)?;
        file.write_all(&bytes)?;
        file.sync_all()?;
        fs::rename(&temporary, &path)?;
        #[cfg(unix)]
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
        Ok(())
    }

    pub fn select_device(&mut self, device: Option<Device>) {
        let previous_id = self.device.as_ref().map(|item| item.id.as_str());
        let next_id = device.as_ref().map(|item| item.id.as_str());
        if previous_id.is_some() && previous_id != next_id {
            self.conversations.clear();
            self.messages.clear();
            self.own_number = None;
        }
        self.device = device;
    }
}

fn cache_file() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| Path::new(&home).join(".cache")))?;
    Some(base.join("sms2").join("state.json"))
}

fn unix_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device(id: &str) -> Device {
        Device {
            id: id.into(),
            name: id.into(),
            reachable: true,
        }
    }

    #[test]
    fn changing_device_clears_private_cached_content() {
        let mut cache = CachedState {
            device: Some(device("phone-a")),
            conversations: vec![],
            messages: HashMap::from([(42, vec![])]),
            own_number: Some("+15551234".into()),
            updated_at: 0,
        };

        cache.select_device(Some(device("phone-b")));

        assert!(cache.messages.is_empty());
        assert!(cache.own_number.is_none());
        assert_eq!(
            cache.device.as_ref().map(|item| item.id.as_str()),
            Some("phone-b")
        );
    }

    #[test]
    fn refreshing_same_device_preserves_cached_content() {
        let mut cache = CachedState {
            device: Some(device("phone-a")),
            conversations: vec![],
            messages: HashMap::from([(42, vec![])]),
            own_number: Some("+15551234".into()),
            updated_at: 0,
        };

        cache.select_device(Some(device("phone-a")));

        assert!(cache.messages.contains_key(&42));
        assert!(cache.own_number.is_some());
    }
}
