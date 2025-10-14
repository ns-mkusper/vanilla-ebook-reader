use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result};
use parking_lot::RwLock;
use serde::Deserialize;
use tokio::task;
use tracing::instrument;
use walkdir::WalkDir;

use crate::model::{Chapter, ChapterId, Ebook, EbookId};
use crate::playback::serde_duration;

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
    Ok(parsed.into_ebook(book_root))
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
    #[serde(default)]
    chapters: Vec<MetadataChapter>,
}

#[derive(Debug, Deserialize)]
struct MetadataChapter {
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

impl MetadataFile {
    fn into_ebook(self, root: &Path) -> Ebook {
        let id = self.id.map(EbookId::from_str).unwrap_or_else(EbookId::new);
        let chapters = self
            .chapters
            .into_iter()
            .enumerate()
            .map(|(idx, chapter)| chapter.into_chapter(root, idx))
            .collect();
        Ebook {
            id,
            title: self.title,
            author: self.author,
            description: self.description,
            cover_art: self.cover_art.map(|p| root.join(p)),
            chapters,
        }
    }
}

impl MetadataChapter {
    fn into_chapter(self, root: &Path, idx: usize) -> Chapter {
        Chapter {
            id: self
                .id
                .map(ChapterId::from_str)
                .unwrap_or_else(ChapterId::new),
            title: self.title,
            file: root.join(self.file),
            duration: self.duration,
            section: self.section,
            chapter_index: self.chapter_index.or_else(|| Some(idx as u32)),
        }
    }
}
