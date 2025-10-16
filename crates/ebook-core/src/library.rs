use std::collections::{BTreeMap, HashSet};
use std::mem;
use std::path::{Component, Path, PathBuf};
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

const AUDIO_EXTENSIONS: &[&str] = &[
    "mp3", "m4a", "m4b", "flac", "wav", "ogg", "oga", "opus", "aac",
];

const TEXT_EXTENSIONS: &[&str] = &[
    "epub", "mobi", "azw", "azw3", "pdf", "txt", "htm", "html", "md", "markdown",
];

fn scan_library(root: PathBuf, metadata_name: String) -> Result<Vec<Ebook>> {
    let mut entries = Vec::new();
    let mut metadata_roots: HashSet<PathBuf> = HashSet::new();

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
            metadata_roots.insert(book_root);
            entries.push(metadata);
        }
    }

    let mut builders: BTreeMap<PathBuf, BookBuilder> = BTreeMap::new();
    for entry in WalkDir::new(&root) {
        let entry = entry?;
        if !entry.file_type().is_file() {
            continue;
        }
        if entry.file_name() == std::ffi::OsStr::new(&metadata_name) {
            continue;
        }
        if is_within_metadata(entry.path(), &metadata_roots) {
            continue;
        }

        let Some(ext) = file_extension(entry.path()) else {
            continue;
        };

        let lower_ext = ext.to_ascii_lowercase();
        let is_audio = AUDIO_EXTENSIONS.contains(&lower_ext.as_str());
        let is_text = TEXT_EXTENSIONS.contains(&lower_ext.as_str());
        if !is_audio && !is_text {
            continue;
        }

        let group_key = derive_group_key(&root, entry.path());
        let title_hint = derive_title_from_group(&group_key, entry.path());
        let builder = builders
            .entry(group_key.clone())
            .or_insert_with(|| BookBuilder::new(group_key.clone(), title_hint));

        if is_audio {
            builder.add_audio(entry.into_path());
        } else if is_text {
            builder.add_text(entry.into_path());
        }
    }

    for builder in builders.into_values() {
        if let Some(ebook) = builder.build()? {
            entries.push(ebook);
        }
    }

    entries.sort_by(|a, b| a.title.to_lowercase().cmp(&b.title.to_lowercase()));
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

fn is_within_metadata(path: &Path, metadata_roots: &HashSet<PathBuf>) -> bool {
    metadata_roots.iter().any(|root| path.starts_with(root))
}

fn file_extension(path: &Path) -> Option<&str> {
    path.extension().and_then(|ext| ext.to_str())
}

fn derive_group_key(root: &Path, path: &Path) -> PathBuf {
    if let Ok(relative) = path.strip_prefix(root) {
        if let Some(component) = relative.components().next() {
            match component {
                Component::Normal(name) => root.join(name),
                _ => path
                    .parent()
                    .map(Path::to_path_buf)
                    .unwrap_or_else(|| root.to_path_buf()),
            }
        } else {
            path.parent()
                .map(Path::to_path_buf)
                .unwrap_or_else(|| root.to_path_buf())
        }
    } else {
        path.parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| root.to_path_buf())
    }
}

fn derive_title_from_group(group_key: &Path, sample: &Path) -> String {
    let candidate = group_key
        .file_stem()
        .or_else(|| group_key.file_name())
        .or_else(|| sample.file_stem())
        .and_then(|os| os.to_str())
        .unwrap_or("Untitled");
    humanize_label(candidate)
}

fn humanize_label(raw: &str) -> String {
    let cleaned = raw
        .replace(|c: char| c == '_' || c == '-', " ")
        .split_whitespace()
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                Some(first) => {
                    let first_upper: String = first.to_uppercase().collect();
                    let rest: String = chars.as_str().to_lowercase();
                    format!("{first_upper}{rest}")
                }
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ");
    if cleaned.is_empty() {
        "Untitled".to_string()
    } else {
        cleaned
    }
}

struct BookBuilder {
    anchor: PathBuf,
    title: String,
    audio_files: Vec<PathBuf>,
    text_files: Vec<PathBuf>,
}

impl BookBuilder {
    fn new(anchor: PathBuf, title: String) -> Self {
        Self {
            anchor,
            title,
            audio_files: Vec::new(),
            text_files: Vec::new(),
        }
    }

    fn add_audio(&mut self, path: PathBuf) {
        self.audio_files.push(path);
    }

    fn add_text(&mut self, path: PathBuf) {
        self.text_files.push(path);
    }

    fn build(mut self) -> Result<Option<Ebook>> {
        if self.audio_files.is_empty() && self.text_files.is_empty() {
            return Ok(None);
        }

        let selected_text = self.select_text_file();
        let mut audio_files = mem::take(&mut self.audio_files);
        audio_files.sort();
        let audio_chapters = audio_files
            .into_iter()
            .enumerate()
            .map(|(idx, path)| AudioChapter {
                id: ChapterId::new(),
                title: path
                    .file_stem()
                    .and_then(|os| os.to_str())
                    .map(humanize_label)
                    .unwrap_or_else(|| format!("Track {}", idx + 1)),
                file: path,
                duration: None,
                section: None,
                chapter_index: Some(idx as u32),
            })
            .collect::<Vec<_>>();

        let mut ebook = Ebook::new(self.title.clone(), None);
        ebook.title = self.title.clone();
        ebook.audio_chapters = audio_chapters;
        ebook.cover_art = find_cover_art(&self.anchor);

        if let Some(text_path) = selected_text {
            let format = file_extension(&text_path)
                .map(TextFormat::from_extension)
                .unwrap_or(TextFormat::Unknown);
            let mut chapters = crate::text::extract_outline_from_text(&text_path, &format)?;
            if chapters.is_empty() {
                chapters.push(TextChapter {
                    id: ChapterId::new(),
                    title: "Full Text".to_string(),
                    locator: None,
                    chapter_index: Some(0),
                });
            }
            let metadata = crate::text::extract_text_metadata(&text_path, &format)?;
            if let Some(title) = metadata.title {
                if !title.trim().is_empty() {
                    ebook.title = title.trim().to_string();
                }
            }
            if ebook.author.is_none() {
                ebook.author = metadata
                    .author
                    .filter(|author| !author.trim().is_empty())
                    .map(|author| author.trim().to_string());
            }
            ebook.text_content = Some(TextContent {
                file: text_path,
                format,
                chapters,
            });
        }

        Ok(Some(ebook))
    }

    fn select_text_file(&self) -> Option<PathBuf> {
        if self.text_files.is_empty() {
            return None;
        }
        let mut files = self.text_files.clone();
        files.sort_by(|a, b| {
            let pa = file_extension(a)
                .map(Self::text_priority)
                .unwrap_or(usize::MAX);
            let pb = file_extension(b)
                .map(Self::text_priority)
                .unwrap_or(usize::MAX);
            pa.cmp(&pb).then_with(|| a.cmp(b))
        });
        files.into_iter().next()
    }

    fn text_priority(ext: &str) -> usize {
        match ext {
            "epub" => 0,
            "mobi" | "azw" | "azw3" => 1,
            "pdf" => 2,
            "html" | "htm" => 3,
            "md" | "markdown" => 4,
            "txt" => 5,
            _ => 6,
        }
    }
}

fn find_cover_art(anchor: &Path) -> Option<PathBuf> {
    let search_dir = if anchor.is_dir() {
        anchor.to_path_buf()
    } else {
        anchor.parent()?.to_path_buf()
    };
    for entry in std::fs::read_dir(search_dir).ok()?.flatten() {
        if !entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
            continue;
        }
        let name = entry.file_name();
        let lower = name.to_string_lossy().to_ascii_lowercase();
        if lower.starts_with("cover.")
            && matches!(
                file_extension(&entry.path()),
                Some("jpg" | "jpeg" | "png" | "webp")
            )
        {
            return Some(entry.path());
        }
    }
    None
}
