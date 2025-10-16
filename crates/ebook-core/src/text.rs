use crate::model::{ChapterId, TextChapter, TextContent, TextFormat};
use anyhow::{anyhow, bail, Context, Result};
use html2text::from_read;
use std::collections::HashMap;
use std::fs;
use std::path::Path;

#[cfg(feature = "epub")]
use epub::doc::{EpubDoc, NavPoint};

#[derive(Debug, Clone)]
pub struct TextSection {
    pub title: String,
    pub body: String,
}

#[derive(Debug, Default, Clone)]
pub struct TextMetadata {
    pub title: Option<String>,
    pub author: Option<String>,
}

/// Attempt to derive a logical chapter outline from a textual source.
///
/// Currently this inspects EPUB files and falls back to the metadata-supplied
/// outline for other formats.
pub fn extract_outline_from_text(path: &Path, format: &TextFormat) -> Result<Vec<TextChapter>> {
    match format {
        TextFormat::Epub => extract_epub_outline(path),
        _ => Ok(Vec::new()),
    }
}

pub fn extract_text_metadata(path: &Path, format: &TextFormat) -> Result<TextMetadata> {
    match format {
        TextFormat::Epub => extract_epub_metadata(path),
        TextFormat::Mobi => extract_mobi_metadata(path),
        _ => Ok(TextMetadata::default()),
    }
}

pub fn load_text_sections(content: &TextContent) -> Result<Vec<TextSection>> {
    match content.format {
        TextFormat::Epub => load_epub_sections(content),
        TextFormat::Mobi => load_mobi_sections(content),
        TextFormat::Pdf => load_pdf_sections(content),
        TextFormat::PlainText | TextFormat::Markdown => load_plain_text_sections(content),
        TextFormat::Html => load_html_sections(content),
        TextFormat::Unknown => load_plain_text_sections(content),
    }
}

fn load_plain_text_sections(content: &TextContent) -> Result<Vec<TextSection>> {
    let text = match fs::read_to_string(&content.file) {
        Ok(raw) => raw,
        Err(_) => {
            let bytes = fs::read(&content.file)
                .with_context(|| format!("failed to read {}", content.file.display()))?;
            String::from_utf8_lossy(&bytes).to_string()
        }
    };
    let title = content
        .chapters
        .first()
        .map(|c| c.title.clone())
        .unwrap_or_else(|| "Document".to_string());
    Ok(vec![TextSection {
        title,
        body: clean_text(&text),
    }])
}

fn load_html_sections(content: &TextContent) -> Result<Vec<TextSection>> {
    let raw = fs::read_to_string(&content.file)
        .with_context(|| format!("failed to read {}", content.file.display()))?;
    let title = content
        .chapters
        .first()
        .map(|c| c.title.clone())
        .unwrap_or_else(|| "Document".to_string());
    let body = from_read(raw.as_bytes(), 80)
        .map_err(|err| anyhow!("failed to render HTML content: {err}"))?;
    Ok(vec![TextSection {
        title,
        body: clean_text(&body),
    }])
}

fn load_pdf_sections(content: &TextContent) -> Result<Vec<TextSection>> {
    let text = pdf_extract::extract_text(&content.file)
        .with_context(|| format!("failed to extract text from {}", content.file.display()))?;
    Ok(vec![TextSection {
        title: content
            .chapters
            .first()
            .map(|c| c.title.clone())
            .unwrap_or_else(|| "Document".to_string()),
        body: clean_text(&text),
    }])
}

fn load_mobi_sections(content: &TextContent) -> Result<Vec<TextSection>> {
    let mobi =
        mobi::Mobi::from_path(&content.file).with_context(|| "failed to parse mobi document")?;
    let html = mobi
        .content_as_string()
        .unwrap_or_else(|_| mobi.content_as_string_lossy());
    let title = {
        let raw = mobi.title();
        if raw.trim().is_empty() {
            content
                .chapters
                .first()
                .map(|c| c.title.clone())
                .unwrap_or_else(|| "Document".to_string())
        } else {
            raw
        }
    };
    let body = from_read(html.as_bytes(), 80)
        .map_err(|err| anyhow!("failed to render MOBI content: {err}"))?;
    Ok(vec![TextSection {
        title,
        body: clean_text(&body),
    }])
}

#[cfg(feature = "epub")]
fn load_epub_sections(content: &TextContent) -> Result<Vec<TextSection>> {
    let mut doc = EpubDoc::new(&content.file)
        .with_context(|| format!("failed to open epub {}", content.file.display()))?;
    if doc.get_num_pages() == 0 {
        bail!("epub contained no readable pages");
    }

    let toc_map = flatten_navpoints(&doc.toc);
    let chapter_locator_map: HashMap<String, String> = content
        .chapters
        .iter()
        .filter_map(|chapter| {
            chapter
                .locator
                .as_ref()
                .map(|loc| (normalize_locator(loc), chapter.title.clone()))
        })
        .collect();

    doc.set_current_page(0)?;
    let mut sections = Vec::new();
    for index in 0..doc.get_num_pages() {
        doc.set_current_page(index)?;
        let html = doc
            .get_current_str()
            .with_context(|| format!("failed to read epub section {}", index))?;
        let path = doc
            .get_current_path()
            .with_context(|| "failed to resolve epub resource path")?;
        let key = normalize_locator(path.to_string_lossy());

        let title = chapter_locator_map
            .get(&key)
            .cloned()
            .or_else(|| toc_map.get(&key).cloned())
            .unwrap_or_else(|| fallback_chapter_title(index));

        let text = from_read(html.as_bytes(), 80)
            .map_err(|err| anyhow!("failed to render EPUB section: {err}"))?;
        sections.push(TextSection {
            title,
            body: clean_text(&text),
        });
    }
    Ok(sections)
}

#[cfg(not(feature = "epub"))]
fn load_epub_sections(_content: &TextContent) -> Result<Vec<TextSection>> {
    bail!("epub support is disabled; recompile with the `epub` feature")
}

#[cfg(feature = "epub")]
fn extract_epub_metadata(path: &Path) -> Result<TextMetadata> {
    let doc = EpubDoc::new(path)
        .with_context(|| format!("failed to read epub metadata at {}", path.display()))?;
    Ok(TextMetadata {
        title: doc.mdata("title"),
        author: doc
            .mdata("creator")
            .or_else(|| doc.mdata("author"))
            .or_else(|| doc.mdata("creator:role:aut")),
    })
}

#[cfg(not(feature = "epub"))]
fn extract_epub_metadata(_path: &Path) -> Result<TextMetadata> {
    Ok(TextMetadata::default())
}

fn extract_mobi_metadata(path: &Path) -> Result<TextMetadata> {
    let mobi = mobi::Mobi::from_path(path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let title = {
        let t = mobi.title();
        if t.trim().is_empty() {
            None
        } else {
            Some(t)
        }
    };
    let author = mobi
        .author()
        .and_then(|a| if a.trim().is_empty() { None } else { Some(a) });
    Ok(TextMetadata { title, author })
}

fn clean_text(input: &str) -> String {
    let normalized = input.replace("\r\n", "\n");
    let mut lines = Vec::new();
    let mut last_was_empty = false;
    for line in normalized.lines() {
        let trimmed = line.trim_end();
        if trimmed.is_empty() {
            if !last_was_empty {
                lines.push(String::new());
            }
            last_was_empty = true;
        } else {
            lines.push(trimmed.trim_start().to_string());
            last_was_empty = false;
        }
    }
    lines.join("\n").trim().to_string()
}

fn fallback_chapter_title(index: usize) -> String {
    format!("Chapter {}", index + 1)
}

fn normalize_locator<S: AsRef<str>>(locator: S) -> String {
    locator.as_ref().trim_start_matches("./").replace('\\', "/")
}

#[cfg(feature = "epub")]
fn flatten_navpoints(navpoints: &[NavPoint]) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for nav in navpoints {
        collect_nav(nav, &mut map);
    }
    map
}

#[cfg(feature = "epub")]
fn collect_nav(nav: &NavPoint, map: &mut HashMap<String, String>) {
    map.insert(
        normalize_locator(nav.content.to_string_lossy()),
        nav.label.clone(),
    );
    for child in &nav.children {
        collect_nav(child, map);
    }
}

#[cfg(feature = "epub")]
fn extract_epub_outline(path: &Path) -> Result<Vec<TextChapter>> {
    let doc =
        EpubDoc::new(path).with_context(|| format!("failed to open epub at {}", path.display()))?;
    let mut chapters = Vec::new();
    let mut index = 0u32;
    for nav in &doc.toc {
        collect_navpoint(nav, &mut index, &mut chapters);
    }
    Ok(chapters)
}

#[cfg(feature = "epub")]
fn collect_navpoint(nav: &NavPoint, index: &mut u32, chapters: &mut Vec<TextChapter>) {
    let current = *index;
    chapters.push(TextChapter {
        id: ChapterId::new(),
        title: nav.label.clone(),
        locator: Some(normalize_locator(nav.content.to_string_lossy())),
        chapter_index: Some(current),
    });
    *index += 1;
    for child in &nav.children {
        collect_navpoint(child, index, chapters);
    }
}

#[cfg(not(feature = "epub"))]
fn extract_epub_outline(_path: &Path) -> Result<Vec<TextChapter>> {
    Ok(Vec::new())
}
