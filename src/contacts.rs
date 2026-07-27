use crate::model::Conversation;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Contact {
    pub name: String,
    pub numbers: Vec<String>,
    pub avatar: String,
}

#[derive(Clone, Debug, Default)]
pub struct ContactBook {
    by_number: HashMap<String, Contact>,
}

impl ContactBook {
    pub fn is_empty(&self) -> bool {
        self.by_number.is_empty()
    }

    pub fn load(device_id: &str) -> Self {
        let Some(directory) = contacts_directory(device_id) else {
            return Self::default();
        };
        let mut book = Self::default();
        let Ok(entries) = fs::read_dir(directory) else {
            return book;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if !matches!(
                path.extension().and_then(|value| value.to_str()),
                Some("vcf" | "vcard")
            ) {
                continue;
            }
            if let Ok(text) = fs::read_to_string(path) {
                if let Some(contact) = parse_vcard(&text) {
                    for number in &contact.numbers {
                        book.by_number
                            .insert(canonical_number(number), contact.clone());
                    }
                }
            }
        }
        book
    }

    pub fn contact(&self, number: &str) -> Option<&Contact> {
        self.by_number.get(&canonical_number(number))
    }

    pub fn decorate(&self, conversations: &mut [Conversation], own_number: Option<&str>) {
        for conversation in conversations {
            let visible: Vec<_> = conversation
                .participants
                .iter()
                .filter(|number| !own_number.is_some_and(|own| numbers_match(number, own)))
                .cloned()
                .collect();
            if !visible.is_empty() {
                conversation.participants = visible;
            }
            let labels: Vec<_> = conversation
                .participants
                .iter()
                .map(|number| {
                    self.contact(number)
                        .map(|contact| contact.name.clone())
                        .unwrap_or_else(|| number.clone())
                })
                .collect();
            if !labels.is_empty() {
                conversation.title = labels.join(", ");
            }
            conversation.avatar = conversation
                .participants
                .first()
                .and_then(|number| self.contact(number))
                .map(|contact| contact.avatar.clone())
                .unwrap_or_default();
        }
    }
}

pub fn infer_own_number(conversations: &[Conversation], previous: Option<&str>) -> Option<String> {
    if let Some(previous) = previous {
        if conversations.iter().any(|conversation| {
            conversation
                .participants
                .iter()
                .any(|number| numbers_match(number, previous))
        }) {
            return Some(previous.to_owned());
        }
    }

    let mut counts: HashMap<String, (String, usize)> = HashMap::new();
    for conversation in conversations
        .iter()
        .filter(|item| item.participants.len() >= 2)
    {
        for number in &conversation.participants {
            let canonical = canonical_number(number);
            let entry = counts
                .entry(canonical)
                .or_insert_with(|| (number.clone(), 0));
            entry.1 += 1;
        }
    }
    counts
        .into_values()
        .max_by_key(|(_, count)| *count)
        .and_then(|(number, count)| (count >= 2).then_some(number))
}

pub fn canonical_number(number: &str) -> String {
    let digits: String = number.chars().filter(char::is_ascii_digit).collect();
    if digits.len() == 11 && digits.starts_with("61") {
        format!("0{}", &digits[2..])
    } else if digits.len() > 10 {
        digits[digits.len() - 10..].to_owned()
    } else {
        digits
    }
}

pub fn numbers_match(left: &str, right: &str) -> bool {
    let left = canonical_number(left);
    let right = canonical_number(right);
    !left.is_empty() && left == right
}

fn contacts_directory(device_id: &str) -> Option<PathBuf> {
    let base = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| Path::new(&home).join(".local/share")))?;
    Some(
        base.join("kpeoplevcard")
            .join(format!("kdeconnect-{device_id}")),
    )
}

fn parse_vcard(input: &str) -> Option<Contact> {
    let unfolded = unfold(input);
    let mut name = String::new();
    let mut numbers = Vec::new();
    let mut avatar = String::new();
    for line in unfolded.lines() {
        if let Some(value) = line.strip_prefix("FN:") {
            name = unescape(value);
        } else if line.starts_with("TEL") {
            if let Some((_, value)) = line.split_once(':') {
                numbers.push(unescape(value));
            }
        } else if line.starts_with("PHOTO") {
            if let Some((metadata, value)) = line.split_once(':') {
                let mime = if metadata.to_ascii_uppercase().contains("PNG") {
                    "image/png"
                } else {
                    "image/jpeg"
                };
                if !value.is_empty() {
                    avatar = format!(
                        "data:{mime};base64,{}",
                        value.replace(char::is_whitespace, "")
                    );
                }
            }
        }
    }
    if name.is_empty() || numbers.is_empty() {
        None
    } else {
        Some(Contact {
            name,
            numbers,
            avatar,
        })
    }
}

fn unfold(input: &str) -> String {
    input
        .replace("\r\n", "\n")
        .replace("\n ", "")
        .replace("\n\t", "")
}

fn unescape(value: &str) -> String {
    value
        .replace("\\n", " ")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .trim()
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_formatted_phone_numbers() {
        assert!(numbers_match("+61 421 495 101", "0421495101"));
    }

    #[test]
    fn parses_folded_photo_and_number() {
        let contact = parse_vcard("BEGIN:VCARD\r\nFN:Kate\r\nTEL;CELL:+61421495101\r\nPHOTO;ENCODING=BASE64;JPEG:abc\r\n def\r\nEND:VCARD").unwrap();
        assert_eq!(contact.name, "Kate");
        assert_eq!(contact.avatar, "data:image/jpeg;base64,abcdef");
    }
}
