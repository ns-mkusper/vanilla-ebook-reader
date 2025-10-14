use crate::model::{ChapterId, TextChapter, TextFormat};
use anyhow::{Context, Result};
use std::path::Path;

#[cfg(feature = "epub")]
use epub::doc::{EpubDoc, NavPoint};

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

#[cfg(feature = "epub")]
fn extract_epub_outline(path: &Path) -> Result<Vec<TextChapter>> {
    let doc =
        EpubDoc::new(path).with_context(|| format!("failed to open epub at {}", path.display()))?;
    let mut chapters = Vec::new();
    let mut index = 0u32;
    for nav in &doc.toc {
        collect_nav(nav, &mut index, &mut chapters);
    }
    Ok(chapters)
}

#[cfg(feature = "epub")]
fn collect_nav(nav: &NavPoint, index: &mut u32, chapters: &mut Vec<TextChapter>) {
    let current = *index;
    chapters.push(TextChapter {
        id: ChapterId::new(),
        title: nav.label.clone(),
        locator: Some(nav.content.to_string_lossy().into_owned()),
        chapter_index: Some(current),
    });
    *index += 1;
    for child in &nav.children {
        collect_nav(child, index, chapters);
    }
}

#[cfg(not(feature = "epub"))]
fn extract_epub_outline(_path: &Path) -> Result<Vec<TextChapter>> {
    Ok(Vec::new())
}
