use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct EbookId(String);

impl EbookId {
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    pub fn from_str(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ChapterId(String);

impl ChapterId {
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    pub fn from_str(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ebook {
    pub id: EbookId,
    pub title: String,
    pub author: Option<String>,
    pub description: Option<String>,
    pub cover_art: Option<PathBuf>,
    pub chapters: Vec<Chapter>,
}

impl Ebook {
    pub fn new(title: impl Into<String>, author: Option<String>) -> Self {
        Self {
            id: EbookId::new(),
            title: title.into(),
            author,
            description: None,
            cover_art: None,
            chapters: Vec::new(),
        }
    }

    pub fn total_duration(&self) -> Duration {
        self.chapters
            .iter()
            .filter_map(|chapter| chapter.duration)
            .fold(Duration::ZERO, |acc, d| acc + d)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Chapter {
    pub id: ChapterId,
    pub title: String,
    pub file: PathBuf,
    #[serde(default, with = "crate::playback::serde_duration::option")]
    pub duration: Option<Duration>,
    pub section: Option<String>,
    pub chapter_index: Option<u32>,
}

impl Chapter {
    pub fn resolves_from(&self, root: impl AsRef<Path>) -> PathBuf {
        let root = root.as_ref();
        if self.file.is_absolute() {
            self.file.clone()
        } else {
            root.join(&self.file)
        }
    }
}
