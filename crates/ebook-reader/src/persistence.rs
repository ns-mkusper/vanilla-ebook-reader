use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use dirs_next::data_local_dir;
use rusqlite::{params, Connection};

use ebook_core::EbookId;

const DB_FILE_NAME: &str = "progress.sqlite";

fn db_path() -> Result<PathBuf> {
    let base = data_local_dir()
        .or_else(|| dirs_next::data_dir())
        .unwrap_or_else(|| Path::new(".").to_path_buf())
        .join("vanilla-ebook-reader");
    fs::create_dir_all(&base)
        .with_context(|| format!("failed to create data directory at {}", base.display()))?;
    Ok(base.join(DB_FILE_NAME))
}

fn open_connection() -> Result<Connection> {
    let path = db_path()?;
    let conn = Connection::open(path).context("failed to open progress database")?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS reader_progress (
            book_id TEXT PRIMARY KEY,
            sentence INTEGER NOT NULL,
            word INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );",
    )
    .context("failed to initialize progress schema")?;
    Ok(conn)
}

pub fn load_progress(book_id: &EbookId) -> Result<Option<(usize, usize)>> {
    let conn = open_connection()?;
    let mut stmt = conn
        .prepare("SELECT sentence, word FROM reader_progress WHERE book_id = ?1")
        .context("failed to prepare progress query")?;
    let mut rows = stmt
        .query([book_id.as_str()])
        .context("failed to query progress")?;
    if let Some(row) = rows.next().context("failed to read progress row")? {
        let sentence: i64 = row.get(0)?;
        let word: i64 = row.get(1)?;
        Ok(Some((sentence.max(0) as usize, word.max(0) as usize)))
    } else {
        Ok(None)
    }
}

pub fn save_progress(book_id: &EbookId, sentence: usize, word: usize) -> Result<()> {
    let conn = open_connection()?;
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    conn.execute(
        "INSERT INTO reader_progress(book_id, sentence, word, updated_at)
         VALUES(?1, ?2, ?3, ?4)
         ON CONFLICT(book_id) DO UPDATE SET sentence = excluded.sentence,
                                            word = excluded.word,
                                            updated_at = excluded.updated_at",
        params![book_id.as_str(), sentence as i64, word as i64, timestamp],
    )
    .context("failed to persist reading progress")?;
    Ok(())
}
