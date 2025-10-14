use std::convert::Infallible;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct EbookId(String);

impl EbookId {
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    pub fn from_string(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for EbookId {
    fn default() -> Self {
        Self::new()
    }
}

impl From<String> for EbookId {
    fn from(value: String) -> Self {
        Self(value)
    }
}

impl From<&str> for EbookId {
    fn from(value: &str) -> Self {
        Self(value.to_owned())
    }
}

impl FromStr for EbookId {
    type Err = Infallible;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(Self::from(s))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ChapterId(String);

impl ChapterId {
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    pub fn from_string(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for ChapterId {
    fn default() -> Self {
        Self::new()
    }
}

impl From<String> for ChapterId {
    fn from(value: String) -> Self {
        Self(value)
    }
}

impl From<&str> for ChapterId {
    fn from(value: &str) -> Self {
        Self(value.to_owned())
    }
}

impl FromStr for ChapterId {
    type Err = Infallible;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(Self::from(s))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ebook {
    pub id: EbookId,
    pub title: String,
    pub author: Option<String>,
    pub description: Option<String>,
    pub cover_art: Option<PathBuf>,
    #[serde(default)]
    pub audio_chapters: Vec<AudioChapter>,
    #[serde(default)]
    pub text_content: Option<TextContent>,
}

impl Ebook {
    pub fn new(title: impl Into<String>, author: Option<String>) -> Self {
        Self {
            id: EbookId::new(),
            title: title.into(),
            author,
            description: None,
            cover_art: None,
            audio_chapters: Vec::new(),
            text_content: None,
        }
    }

    pub fn total_audio_duration(&self) -> Duration {
        self.audio_chapters
            .iter()
            .filter_map(|chapter| chapter.duration)
            .fold(Duration::ZERO, |acc, d| acc + d)
    }

    pub fn has_audio(&self) -> bool {
        !self.audio_chapters.is_empty()
    }

    pub fn has_text(&self) -> bool {
        self.text_content.is_some()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioChapter {
    pub id: ChapterId,
    pub title: String,
    pub file: PathBuf,
    #[serde(default, with = "crate::playback::serde_duration::option")]
    pub duration: Option<Duration>,
    pub section: Option<String>,
    pub chapter_index: Option<u32>,
}

impl AudioChapter {
    pub fn resolves_from(&self, root: impl AsRef<Path>) -> PathBuf {
        let root = root.as_ref();
        if self.file.is_absolute() {
            self.file.clone()
        } else {
            root.join(&self.file)
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TextFormat {
    #[serde(rename = "epub")]
    Epub,
    #[serde(rename = "mobi")]
    Mobi,
    #[serde(rename = "pdf")]
    Pdf,
    #[serde(other)]
    Unknown,
}

impl TextFormat {
    pub fn from_extension(ext: &str) -> Self {
        match ext.to_ascii_lowercase().as_str() {
            "epub" => Self::Epub,
            "mobi" | "azw" | "azw3" => Self::Mobi,
            "pdf" => Self::Pdf,
            _ => Self::Unknown,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextChapter {
    pub id: ChapterId,
    pub title: String,
    #[serde(default)]
    pub locator: Option<String>,
    #[serde(default)]
    pub chapter_index: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextContent {
    pub file: PathBuf,
    pub format: TextFormat,
    #[serde(default)]
    pub chapters: Vec<TextChapter>,
}

impl TextContent {
    pub fn resolves_from(&self, root: impl AsRef<Path>) -> PathBuf {
        let root = root.as_ref();
        if self.file.is_absolute() {
            self.file.clone()
        } else {
            root.join(&self.file)
        }
    }
}
