use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result};
use parking_lot::RwLock;
use serde::Deserialize;
use tokio::task;
use tracing::instrument;
use walkdir::WalkDir;

use crate::model::{AudioChapter, ChapterId, Ebook, EbookId, TextChapter, TextContent, TextFormat};
use crate::{playback::serde_duration, text::extract_outline_from_text};

#[derive(Debug, Clone)]
pub struct LibraryConfig {
    pub root: PathBuf,
    pub metadata_file: String,
}

impl LibraryConfig {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self {
            root: root.into(),
            metadata_file: "book.json".to_string(),
        }
    }

    pub fn metadata_file(mut self, name: impl Into<String>) -> Self {
        self.metadata_file = name.into();
        self
    }
}

#[derive(Debug, Clone, Default)]
pub struct Library {
    ebooks: Arc<RwLock<Vec<Ebook>>>,
}

impl Library {
    pub fn iter(&self) -> Vec<Ebook> {
        self.ebooks.read().clone()
    }

    pub fn get(&self, id: &EbookId) -> Option<Ebook> {
        self.ebooks
            .read()
            .iter()
            .find(|entry| entry.id == *id)
            .cloned()
    }

    fn replace_all(&self, data: Vec<Ebook>) {
        *self.ebooks.write() = data;
    }
}

#[derive(Debug)]
pub struct LibraryLoader {
    config: LibraryConfig,
}

impl LibraryLoader {
    pub fn new(config: LibraryConfig) -> Self {
        Self { config }
    }

    #[instrument(skip(self))]
    pub async fn load(&self) -> Result<Library> {
        let root = self.config.root.clone();
        let metadata_file = self.config.metadata_file.clone();
        let ebooks = task::spawn_blocking(move || scan_library(root, metadata_file)).await??;
        let library = Library::default();
        library.replace_all(ebooks);
        Ok(library)
    }
}

fn scan_library(root: PathBuf, metadata_name: String) -> Result<Vec<Ebook>> {
    let mut entries = Vec::new();
    for entry in WalkDir::new(&root) {
        let entry = entry?;
        if !entry.file_type().is_file() {
            continue;
        }
        if entry.file_name() == std::ffi::OsStr::new(&metadata_name) {
            let book_root = entry
                .path()
                .parent()
                .map(Path::to_path_buf)
                .context("metadata file has no parent")?;
            let metadata = read_metadata(entry.path(), &book_root)?;
            entries.push(metadata);
        }
    }
    Ok(entries)
}

fn read_metadata(path: &Path, book_root: &Path) -> Result<Ebook> {
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read metadata from {}", path.display()))?;
    let parsed: MetadataFile = serde_json::from_str(&raw)
        .with_context(|| format!("failed to parse metadata from {}", path.display()))?;
    parsed.into_ebook(book_root)
}

#[derive(Debug, Deserialize)]
struct MetadataFile {
    #[serde(default)]
    id: Option<String>,
    title: String,
    #[serde(default)]
    author: Option<String>,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    cover_art: Option<String>,
    #[serde(default, rename = "audio_chapters", alias = "chapters")]
    audio_chapters: Vec<MetadataAudioChapter>,
    #[serde(default)]
    text: Option<MetadataText>,
}

#[derive(Debug, Deserialize)]
struct MetadataAudioChapter {
    #[serde(default)]
    id: Option<String>,
    title: String,
    file: String,
    #[serde(default, with = "serde_duration::option")]
    duration: Option<std::time::Duration>,
    #[serde(default)]
    section: Option<String>,
    #[serde(default)]
    chapter_index: Option<u32>,
}

#[derive(Debug, Deserialize)]
struct MetadataText {
    file: String,
    #[serde(default)]
    format: Option<String>,
    #[serde(default)]
    toc: Vec<MetadataTextChapter>,
}

#[derive(Debug, Deserialize)]
struct MetadataTextChapter {
    title: String,
    #[serde(default)]
    locator: Option<String>,
}

impl MetadataFile {
    fn into_ebook(self, root: &Path) -> Result<Ebook> {
        let id = self.id.map(EbookId::from).unwrap_or_default();
        let audio_chapters = self
            .audio_chapters
            .into_iter()
            .enumerate()
            .map(|(idx, chapter)| chapter.into_chapter(root, idx))
            .collect();
        let text_content = match self.text {
            Some(text) => Some(text.into_text(root)?),
            None => None,
        };
        Ok(Ebook {
            id,
            title: self.title,
            author: self.author,
            description: self.description,
            cover_art: self.cover_art.map(|p| root.join(p)),
            audio_chapters,
            text_content,
        })
    }
}

impl MetadataAudioChapter {
    fn into_chapter(self, root: &Path, idx: usize) -> AudioChapter {
        AudioChapter {
            id: self.id.map(ChapterId::from).unwrap_or_default(),
            title: self.title,
            file: root.join(self.file),
            duration: self.duration,
            section: self.section,
            chapter_index: self.chapter_index.or(Some(idx as u32)),
        }
    }
}

impl MetadataText {
    fn into_text(self, root: &Path) -> Result<TextContent> {
        let path = root.join(&self.file);
        let format = self
            .format
            .as_deref()
            .map(TextFormat::from_extension)
            .unwrap_or_else(|| {
                path.extension()
                    .and_then(|ext| ext.to_str())
                    .map(TextFormat::from_extension)
                    .unwrap_or(TextFormat::Unknown)
            });

        let mut chapters: Vec<TextChapter> = self
            .toc
            .into_iter()
            .enumerate()
            .map(|(idx, chapter)| chapter.into_chapter(idx))
            .collect();

        if chapters.is_empty() {
            chapters = extract_outline_from_text(&path, &format)?;
        }

        Ok(TextContent {
            file: path,
            format,
            chapters,
        })
    }
}

impl MetadataTextChapter {
    fn into_chapter(self, idx: usize) -> TextChapter {
        TextChapter {
            id: ChapterId::new(),
            title: self.title,
            locator: self.locator,
            chapter_index: Some(idx as u32),
        }
    }
}
