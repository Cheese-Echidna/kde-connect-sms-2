use crate::model::{Conversation, Device, UiMessage};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::io;
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
        fs::write(
            &temporary,
            serde_json::to_vec(self).map_err(io::Error::other)?,
        )?;
        fs::rename(temporary, path)
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
