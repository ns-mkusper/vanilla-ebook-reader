use std::cell::RefCell;
use std::collections::HashMap;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};
#[cfg(feature = "native-audio")]
use std::sync::atomic::AtomicU32;
use std::sync::Arc;
use std::time::Duration;

#[cfg(feature = "native-audio")]
use std::sync::atomic::AtomicBool;
#[cfg(feature = "native-audio")]
use std::thread;

#[cfg(feature = "native-audio")]
use anyhow::anyhow;
#[cfg(feature = "native-audio")]
use crate::tts::{self, SynthesisOptions};
use anyhow::{Context, Result};
use ebook_core::{
    library::{LibraryConfig, LibraryLoader},
    playback::{PlaybackCommand, PlaybackController, PlaybackEvent},
    sentence_segments,
    text::{load_text_sections, TextSection},
    Ebook, EbookId,
};

use crate::persistence::{load_progress, save_progress};

#[cfg(feature = "native-audio")]
use rodio::buffer::SamplesBuffer;
#[cfg(feature = "native-audio")]
use rodio::{OutputStream, Sink};
#[cfg(feature = "native-audio")]
use std::time::Instant;

use slint::{Image, Rgba8Pixel, SharedPixelBuffer, SharedString, VecModel};
use tokio::runtime::{Handle, Runtime};
use tokio::sync::mpsc::Receiver;

slint::include_modules!();

static SESSION_COUNTER: AtomicUsize = AtomicUsize::new(1);

thread_local! {
    static READER_SESSIONS: RefCell<HashMap<usize, ReaderSession>> = RefCell::new(HashMap::new());
    static ACTIVE_WINDOWS: RefCell<HashMap<usize, ReaderWindow>> = RefCell::new(HashMap::new());
}

const DEFAULT_TTS_RATE: f32 = 1.0;
const TTS_MIN_RATE: f32 = 0.5;
const TTS_MAX_RATE: f32 = 2.5;
#[cfg(feature = "native-audio")]
const MIN_HIGHLIGHT_STEP_MS: u64 = 15;
#[cfg(feature = "native-audio")]
const FALLBACK_WORD_MS: u64 = 120;

#[derive(Clone)]
struct SentenceData {
    text: String,
    words: Vec<String>,
}

struct ReaderSession {
    book_id: EbookId,
    sections: Vec<TextSection>,
    current_chapter: usize,
    window: slint::Weak<ReaderWindow>,
    sentences: Vec<SentenceData>,
    current_sentence: usize,
    current_word: usize,
    tts_rate: f32,
    #[cfg(feature = "native-audio")]
    tts_engine: Option<Arc<dyn tts::SpeechEngine>>,
    #[cfg(feature = "native-audio")]
    tts_voice: Option<String>,
    #[cfg(feature = "native-audio")]
    tts_rate_handle: Arc<AtomicU32>,
    #[cfg(feature = "native-audio")]
    tts: Option<TtsPlayback>,
}

#[cfg(feature = "native-audio")]
struct TtsPlayback {
    cancel: Arc<AtomicBool>,
    finished: Arc<AtomicBool>,
}

pub fn run() -> Result<()> {
    setup_tracing()?;

    // Keep runtime alive for async tasks while UI runs on main thread
    let runtime = Runtime::new().context("failed to create tokio runtime")?;
    let handle = runtime.handle().clone();

    let library_root = detect_library_root();
    tracing::info!(root = %library_root.display(), "loading library");

    let loader = LibraryLoader::new(LibraryConfig::new(&library_root));
    let library = runtime
        .block_on(loader.load())
        .context("failed to load ebook library")?;

    let books: Arc<Vec<Ebook>> = Arc::new(library.iter());
    #[cfg(feature = "native-audio")]
    let (controller, events, _audio_stream_guard) = runtime.block_on(async {
        let (backend, stream) = create_backend().await?;
        let (controller, events) = PlaybackController::new(backend);
        Ok::<_, anyhow::Error>((controller, events, stream))
    })?;
    #[cfg(not(feature = "native-audio"))]
    let (controller, events) = runtime.block_on(async {
        let backend = create_backend().await?;
        Ok::<_, anyhow::Error>(PlaybackController::new(backend))
    })?;

    let window = MainWindow::new().context("failed to create MainWindow")?;
    window.set_status_text(SharedString::from("Ready"));

    populate_ui(&window, &books);

    wire_play_handler(&window, &books, controller.command_sender(), handle.clone());
    wire_read_handler(&window, &books, handle.clone());
    spawn_event_listener(window.as_weak(), events, handle);

    let _ = window.run();
    Ok(())
}

fn populate_ui(window: &MainWindow, books: &Arc<Vec<Ebook>>) {
    let items: Vec<_> = books
        .iter()
        .map(|book| EbookItem {
            title: SharedString::from(book.title.clone()),
            author: SharedString::from(
                book.author
                    .as_deref()
                    .map(|a| {
                        if a.trim().is_empty() {
                            "Unknown Author"
                        } else {
                            a
                        }
                    })
                    .unwrap_or("Unknown Author"),
            ),
            detail: SharedString::from(describe_book(book)),
            has_audio: book.has_audio(),
            has_text: book.has_text(),
        })
        .collect();
    let model = VecModel::from(items);
    window.set_ebooks(Rc::new(model).into());
}

fn wire_play_handler(
    window: &MainWindow,
    books: &Arc<Vec<Ebook>>,
    sender: tokio::sync::mpsc::Sender<PlaybackCommand>,
    handle: Handle,
) {
    let books = Arc::clone(books);
    let window_handle = window.as_weak();
    window.on_play_selected(move |index| {
        if let Some(window) = window_handle.upgrade() {
            window.set_status_text(SharedString::from("Loading audio…"));
        }
        let sender = sender.clone();
        let books = Arc::clone(&books);
        let handle = handle.clone();
        let status_handle = window_handle.clone();
        handle.spawn(async move {
            if let Some(book) = books.get(index as usize).cloned() {
                if let Some(chapter) = book.audio_chapters.first().cloned() {
                    if let Err(err) = sender.send(PlaybackCommand::LoadAndPlay(chapter)).await {
                        tracing::warn!(?err, "failed to send playback command");
                    }
                } else if book.has_text() {
                    let message = format!(
                        "{} has no audio tracks; try the Read option instead",
                        book.title
                    );
                    tracing::info!("{}", message);
                    notify_status(status_handle.clone(), message);
                }
            }
        });
    });
}

fn wire_read_handler(window: &MainWindow, books: &Arc<Vec<Ebook>>, handle: Handle) {
    let books = Arc::clone(books);
    let window_handle = window.as_weak();
    window.on_read_selected(move |index| {
        tracing::debug!(%index, "read button clicked");
        if let Some(window) = window_handle.upgrade() {
            window.set_status_text(SharedString::from("Opening reader…"));
        }
        let books = Arc::clone(&books);
        let handle = handle.clone();
        let window_noti = window_handle.clone();
        handle.spawn(async move {
            let Some(book) = books.get(index as usize).cloned() else {
                tracing::warn!(%index, "read click referenced missing book");
                notify_status(window_noti.clone(), "Book could not be found");
                return;
            };
            let Some(text_content) = book.text_content.clone() else {
                tracing::warn!(book_title = %book.title, "book has no text content for reader");
                notify_status(
                    window_noti.clone(),
                    format!("{} has no readable text.", book.title),
                );
                return;
            };

            match tokio::task::spawn_blocking(move || load_text_sections(&text_content)).await {
                Ok(Ok(sections)) => {
                    tracing::debug!(book_title = %book.title, sections = sections.len(), "loaded text sections");
                    let status_handle = window_noti.clone();
                    slint::invoke_from_event_loop(move || {
                        if let Err(err) = show_reader_window(book, sections) {
                            if let Some(window) = status_handle.upgrade() {
                                tracing::error!(?err, "failed to open reader window");
                                window.set_status_text(SharedString::from(format!(
                                    "Failed to open reader: {err:#}"
                                )));
                            }
                        } else if let Some(window) = status_handle.upgrade() {
                            window.set_status_text(SharedString::from("Ready"));
                        }
                    })
                    .ok();
                }
                Ok(Err(err)) => {
                    tracing::error!(?err, "loading text sections failed");
                    notify_status(window_noti, format!("Failed to load text: {err:#}"));
                }
                Err(err) => {
                    tracing::error!(?err, "spawn blocking for text load failed");
                    notify_status(window_noti, format!("Failed to load text: {err}"));
                }
            }
        });
    });
}

fn spawn_event_listener(
    window: slint::Weak<MainWindow>,
    mut events: Receiver<PlaybackEvent>,
    handle: Handle,
) {
    handle.spawn(async move {
        while let Some(event) = events.recv().await {
            if let Some(window) = window.upgrade() {
                match event {
                    PlaybackEvent::ChapterStarted(chapter) => {
                        window.set_status_text(SharedString::from(format!(
                            "Playing: {}",
                            chapter.title
                        )));
                    }
                    PlaybackEvent::ChapterComplete(chapter) => {
                        window.set_status_text(SharedString::from(format!(
                            "Finished: {}",
                            chapter.title
                        )));
                    }
                    PlaybackEvent::ChapterFailed { chapter, error } => {
                        window.set_status_text(SharedString::from(format!(
                            "Error playing {}: {}",
                            chapter.title, error
                        )));
                    }
                }
            }
        }
    });
}

fn notify_status(handle: slint::Weak<MainWindow>, message: impl Into<String>) {
    let text = SharedString::from(message.into());
    slint::invoke_from_event_loop(move || {
        if let Some(window) = handle.upgrade() {
            window.set_status_text(text.clone());
        }
    })
    .ok();
}

fn show_reader_window(book: Ebook, mut sections: Vec<TextSection>) -> Result<()> {
    if sections.is_empty() {
        sections.push(TextSection {
            title: "Document".to_string(),
            body: "No readable content was found in this file.".to_string(),
            images: Vec::new(),
        });
    }

    let reader = ReaderWindow::new().context("failed to create reader window")?;
    reader.set_book_title(SharedString::from(book.title.clone()));

    let chapter_items: Vec<_> = sections
        .iter()
        .map(|section| ReaderChapter {
            title: SharedString::from(section.title.clone()),
        })
        .collect();
    reader.set_chapters(Rc::new(VecModel::from(chapter_items)).into());

    let session_id = SESSION_COUNTER.fetch_add(1, Ordering::Relaxed);

    #[cfg(feature = "native-audio")]
    let engine_handle = tts::resolve_from_environment();
    #[cfg(feature = "native-audio")]
    let resolved_engine = if engine_handle.engine.id() == "null" {
        tracing::warn!("no speech engine available; TTS playback will be disabled");
        None
    } else {
        Some(engine_handle.engine.clone())
    };

    #[cfg(feature = "native-audio")]
    let rate_handle = Arc::new(AtomicU32::new(rate_to_atomic(DEFAULT_TTS_RATE)));

    let session = ReaderSession {
        book_id: book.id.clone(),
        sections: sections.clone(),
        current_chapter: 0,
        window: reader.as_weak(),
        sentences: Vec::new(),
        current_sentence: 0,
        current_word: 0,
        tts_rate: DEFAULT_TTS_RATE,
        #[cfg(feature = "native-audio")]
        tts_engine: resolved_engine,
        #[cfg(feature = "native-audio")]
        tts_voice: engine_handle.voice.clone(),
        #[cfg(feature = "native-audio")]
        tts_rate_handle: rate_handle.clone(),
        #[cfg(feature = "native-audio")]
        tts: None,
    };

    READER_SESSIONS.with(|map| {
        map.borrow_mut().insert(session_id, session);
    });

    set_tts_rate(session_id, DEFAULT_TTS_RATE)?;

    change_chapter(session_id, 0, false)?;

    if let Some((saved_sentence, saved_word)) = load_progress(&book.id).ok().flatten() {
        let _ = set_sentence(session_id, saved_sentence, saved_word, false);
    }

    let reader_weak = reader.as_weak();
    reader.on_chapter_selected(move |idx| {
        #[cfg(feature = "native-audio")]
        {
            if let Err(err) = stop_tts(session_id, false) {
                tracing::warn!(?err, "failed to stop TTS before chapter change");
            }
        }
        if let Err(err) = change_chapter(session_id, idx as usize, true) {
            tracing::warn!(?err, "failed to change chapter");
        }
        if let Some(window) = reader_weak.upgrade() {
            let _ = window.set_selected_index(idx);
        }
    });

    let reader_weak = reader.as_weak();
    reader.on_sentence_selected(move |idx| {
        #[cfg(feature = "native-audio")]
        {
            if let Err(err) = stop_tts(session_id, false) {
                tracing::warn!(?err, "failed to stop TTS before seeking sentence");
            }
        }
        if let Err(err) = set_sentence(session_id, idx as usize, 0, true) {
            tracing::warn!(?err, "failed to update sentence selection");
        }
        if let Some(window) = reader_weak.upgrade() {
            window.set_active_sentence_index(idx);
        }
    });

    let rate_session = session_id;
    reader.on_tts_rate_changed(move |rate| {
        if let Err(err) = set_tts_rate(rate_session, rate) {
            tracing::warn!(?err, "failed to update TTS rate");
        }
    });

    #[cfg(feature = "native-audio")]
    {
        let id = session_id;
        reader.on_tts_play(move || {
            if let Err(err) = start_tts(id) {
                tracing::warn!(?err, "failed to start TTS");
            }
        });

        let id = session_id;
        reader.on_tts_pause(move || {
            if let Err(err) = pause_tts(id) {
                tracing::warn!(?err, "failed to pause TTS");
            }
        });

        let id = session_id;
        reader.on_tts_stop(move || {
            if let Err(err) = stop_tts(id, true) {
                tracing::warn!(?err, "failed to stop TTS");
            }
        });

        let id = session_id;
        reader.on_tts_forward_sentence(move || {
            if let Err(err) = stop_tts(id, false) {
                tracing::warn!(?err, "failed to stop TTS before sentence skip");
            }
            if let Err(err) = step_sentence(id, 1, true) {
                tracing::warn!(?err, "failed to advance sentence");
            }
        });

        let id = session_id;
        reader.on_tts_backward_sentence(move || {
            if let Err(err) = stop_tts(id, false) {
                tracing::warn!(?err, "failed to stop TTS before rewinding sentence");
            }
            if let Err(err) = step_sentence(id, -1, true) {
                tracing::warn!(?err, "failed to rewind sentence");
            }
        });

        let id = session_id;
        reader.on_tts_jump_forward(move || {
            if let Err(err) = stop_tts(id, false) {
                tracing::warn!(?err, "failed to stop TTS before jump");
            }
            if let Err(err) = jump_sentences(id, 2, true) {
                tracing::warn!(?err, "failed to jump forward");
            }
        });

        let id = session_id;
        reader.on_tts_jump_backward(move || {
            if let Err(err) = stop_tts(id, false) {
                tracing::warn!(?err, "failed to stop TTS before jump");
            }
            if let Err(err) = jump_sentences(id, -2, true) {
                tracing::warn!(?err, "failed to jump backward");
            }
        });
    }

    #[cfg(not(feature = "native-audio"))]
    {
        reader.on_tts_play(move || {
            tracing::info!("TTS requires the native-audio feature to be enabled");
        });
        reader.on_tts_pause(|| {});
        reader.on_tts_stop(|| {});
        reader.on_tts_forward_sentence(|| {});
        reader.on_tts_backward_sentence(|| {});
        reader.on_tts_jump_forward(|| {});
        reader.on_tts_jump_backward(|| {});
    }

    let close_id = session_id;
    let close_window = reader.as_weak();
    reader.on_request_close(move || {
        #[cfg(feature = "native-audio")]
        {
            if let Err(err) = stop_tts(close_id, false) {
                tracing::warn!(?err, "failed to stop TTS on close");
            }
        }
        if let Some(window) = close_window.upgrade() {
            if let Err(err) = window.hide() {
                tracing::warn!(?err, "failed to hide reader window");
            }
        }
        READER_SESSIONS.with(|map| {
            map.borrow_mut().remove(&close_id);
        });
        ACTIVE_WINDOWS.with(|map| {
            map.borrow_mut().remove(&close_id);
        });
    });

    reader.show()?;
    ACTIVE_WINDOWS.with(|map| {
        map.borrow_mut().insert(session_id, reader);
    });
    Ok(())
}

fn detect_library_root() -> PathBuf {
    if let Ok(env) = std::env::var("VANILLA_READER_LIBRARY_ROOT") {
        return PathBuf::from(env);
    }
    if let Some(arg1) = std::env::args().nth(1) {
        return PathBuf::from(arg1);
    }
    PathBuf::from("assets/library")
}

fn setup_tracing() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .with_target(false)
        .compact()
        .try_init()
        .ok();
    Ok(())
}

fn format_duration(duration: Duration) -> String {
    let total_secs = duration.as_secs();
    let hours = total_secs / 3600;
    let minutes = (total_secs % 3600) / 60;
    let seconds = total_secs % 60;
    if hours > 0 {
        format!("{hours:02}:{minutes:02}:{seconds:02}")
    } else {
        format!("{minutes:02}:{seconds:02}")
    }
}

fn describe_book(book: &Ebook) -> String {
    match (book.has_audio(), book.has_text()) {
        (true, true) => {
            let total = book.total_audio_duration();
            if total == Duration::ZERO {
                "Audio • Text".to_string()
            } else {
                format!("Audio • {} • Text", format_duration(total))
            }
        }
        (true, false) => {
            let total = book.total_audio_duration();
            if total == Duration::ZERO {
                "Audio".to_string()
            } else {
                format!("Audio • {}", format_duration(total))
            }
        }
        (false, true) => "Text".to_string(),
        _ => "Uncategorized".to_string(),
    }
}

fn format_tts_rate(rate: f32) -> SharedString {
    SharedString::from(format!("{rate:.1}×"))
}

fn build_reader_images(section: &TextSection) -> Vec<ReaderImage> {
    section
        .images
        .iter()
        .filter_map(|image| {
            decode_section_image(&image.data).map(|(source, width, height)| {
                ReaderImage {
                    source,
                    description: SharedString::from(
                        image.description.clone().unwrap_or_default(),
                    ),
                    natural_width: width,
                    natural_height: height,
                }
            })
        })
        .collect()
}

fn decode_section_image(data: &[u8]) -> Option<(Image, f32, f32)> {
    match image::load_from_memory(data) {
        Ok(dynamic) => {
            let rgba = dynamic.to_rgba8();
            let (width, height) = rgba.dimensions();
            if width == 0 || height == 0 {
                return None;
            }
            let buffer = SharedPixelBuffer::<Rgba8Pixel>::clone_from_slice(
                rgba.as_raw(),
                width,
                height,
            );
            Some((Image::from_rgba8(buffer), width as f32, height as f32))
        }
        Err(err) => {
            tracing::warn!(?err, "failed to decode embedded image");
            None
        }
    }
}

fn set_tts_rate(session_id: usize, rate: f32) -> Result<()> {
    let clamped = rate.clamp(TTS_MIN_RATE, TTS_MAX_RATE);
    READER_SESSIONS.with(|sessions| {
        let mut map = sessions.borrow_mut();
        if let Some(session) = map.get_mut(&session_id) {
            session.tts_rate = clamped;
            #[cfg(feature = "native-audio")]
            {
                session
                    .tts_rate_handle
                    .store(rate_to_atomic(clamped), Ordering::SeqCst);
            }
            if let Some(window) = session.window.upgrade() {
                window.set_tts_rate(clamped);
                window.set_tts_rate_label(format_tts_rate(clamped));
            }
        }
        Ok(())
    })
}

fn sentence_items(sentences: &[SentenceData]) -> Vec<ReaderSentence> {
    sentences
        .iter()
        .map(|s| ReaderSentence {
            text: SharedString::from(s.text.clone()),
        })
        .collect()
}

fn word_items(words: &[String]) -> Vec<ReaderWord> {
    words
        .iter()
        .map(|w| ReaderWord {
            text: SharedString::from(w.clone()),
        })
        .collect()
}

fn update_reader_view(session: &mut ReaderSession) {
    if let Some(window) = session.window.upgrade() {
        let sentence_model = Rc::new(VecModel::from(sentence_items(&session.sentences)));
        window.set_sentences(sentence_model.into());

        if let Some(sentence) = session.sentences.get(session.current_sentence) {
            window.set_active_sentence_text(SharedString::from(sentence.text.clone()));
            let word_model = Rc::new(VecModel::from(word_items(&sentence.words)));
            window.set_active_sentence_words(word_model.into());
            let word_count = sentence.words.len();
            if word_count == 0 {
                window.set_active_word_index(-1);
                session.current_word = 0;
            } else {
                let clamped = session.current_word.min(word_count - 1);
                session.current_word = clamped;
                window.set_active_word_index(clamped as i32);
            }
            window.set_active_sentence_index(session.current_sentence as i32);
        } else {
            window.set_active_sentence_text(SharedString::from(""));
            window.set_active_sentence_words(
                Rc::new(VecModel::from(Vec::<ReaderWord>::new())).into(),
            );
            window.set_active_sentence_index(-1);
            window.set_active_word_index(-1);
            session.current_sentence = 0;
            session.current_word = 0;
        }
    }
}

fn change_chapter(session_id: usize, chapter_idx: usize, persist: bool) -> Result<()> {
    READER_SESSIONS.with(|sessions| {
        let mut map = sessions.borrow_mut();
        let session = match map.get_mut(&session_id) {
            Some(s) => s,
            None => return Ok(()),
        };

        if chapter_idx >= session.sections.len() {
            return Ok(());
        }

        session.current_chapter = chapter_idx;
        let section = &session.sections[chapter_idx];
        if let Some(window) = session.window.upgrade() {
            window.set_selected_index(chapter_idx as i32);
            window.set_chapter_title(SharedString::from(section.title.clone()));
            window.set_content(SharedString::from(section.body.clone()));
            let image_items = Rc::new(VecModel::from(build_reader_images(section)));
            window.set_content_images(image_items.into());
        }

        session.sentences = sentence_segments(&section.body)
            .into_iter()
            .map(|seg| SentenceData {
                text: seg.text,
                words: seg.words,
            })
            .collect();
        session.current_sentence = 0;
        session.current_word = 0;
        update_reader_view(session);

        if persist {
            save_progress(
                &session.book_id,
                session.current_sentence,
                session.current_word,
            )?;
        }

        Ok(())
    })
}

fn set_sentence(
    session_id: usize,
    sentence_idx: usize,
    word_idx: usize,
    persist: bool,
) -> Result<()> {
    READER_SESSIONS.with(|sessions| {
        let mut map = sessions.borrow_mut();
        let session = match map.get_mut(&session_id) {
            Some(s) => s,
            None => return Ok(()),
        };

        if session.sentences.is_empty() {
            session.current_sentence = 0;
            session.current_word = 0;
            update_reader_view(session);
            return Ok(());
        }

        let clamped_sentence = sentence_idx.min(session.sentences.len() - 1);
        session.current_sentence = clamped_sentence;
        let word_count = session.sentences[clamped_sentence].words.len();
        session.current_word = if word_count == 0 {
            0
        } else {
            word_idx.min(word_count - 1)
        };

        update_reader_view(session);

        if persist {
            save_progress(
                &session.book_id,
                session.current_sentence,
                session.current_word,
            )?;
        }

        Ok(())
    })
}

#[cfg(feature = "native-audio")]
fn set_active_word(session_id: usize, word_idx: usize, persist: bool) -> Result<()> {
    READER_SESSIONS.with(|sessions| {
        let mut map = sessions.borrow_mut();
        let session = match map.get_mut(&session_id) {
            Some(s) => s,
            None => return Ok(()),
        };

        if session.sentences.is_empty() {
            if let Some(window) = session.window.upgrade() {
                window.set_active_word_index(-1);
            }
            session.current_word = 0;
            return Ok(());
        }

        let word_count = session.sentences[session.current_sentence].words.len();
        if let Some(window) = session.window.upgrade() {
            if word_count == 0 {
                window.set_active_word_index(-1);
                session.current_word = 0;
            } else {
                let clamped = word_idx.min(word_count - 1);
                session.current_word = clamped;
                window.set_active_word_index(clamped as i32);
            }
        }

        if persist {
            save_progress(
                &session.book_id,
                session.current_sentence,
                session.current_word,
            )?;
        }

        Ok(())
    })
}

#[cfg(feature = "native-audio")]
fn step_sentence(session_id: usize, delta: isize, persist: bool) -> Result<()> {
    let target = READER_SESSIONS.with(|sessions| {
        let map = sessions.borrow();
        map.get(&session_id).and_then(|session| {
            if session.sentences.is_empty() {
                None
            } else {
                let len = session.sentences.len() as isize;
                let mut idx = session.current_sentence as isize + delta;
                if idx < 0 {
                    idx = 0;
                }
                if idx >= len {
                    idx = len - 1;
                }
                Some(idx as usize)
            }
        })
    });

    if let Some(idx) = target {
        set_sentence(session_id, idx, 0, persist)?;
    }
    Ok(())
}

#[cfg(feature = "native-audio")]
fn jump_sentences(session_id: usize, delta_sentences: isize, persist: bool) -> Result<()> {
    step_sentence(session_id, delta_sentences, persist)
}

#[cfg(feature = "native-audio")]
fn start_tts(session_id: usize) -> Result<()> {
    let (
        sentences,
        start_sentence,
        start_word,
        rate_handle,
        engine,
        voice,
        cancel_flag,
        finished_flag,
    ) = READER_SESSIONS.with(|sessions| {
        let mut map = sessions.borrow_mut();
        let session = map
            .get_mut(&session_id)
            .ok_or_else(|| anyhow!("reader session is not available"))?;

        if session.sentences.is_empty() {
            return Err(anyhow!("no text available for TTS"));
        }

        if session.tts.is_some() {
            return Err(anyhow!("TTS is already running"));
        }

        let engine = session
            .tts_engine
            .clone()
            .ok_or_else(|| anyhow!("no speech engine configured"))?;

        let cancel = Arc::new(AtomicBool::new(false));
        let finished = Arc::new(AtomicBool::new(false));

        session.tts = Some(TtsPlayback {
            cancel: cancel.clone(),
            finished: finished.clone(),
        });

        Ok((
            session.sentences.clone(),
            session.current_sentence,
            session.current_word,
            session.tts_rate_handle.clone(),
            engine,
            session.tts_voice.clone(),
            cancel,
            finished,
        ))
    })?;

    thread::spawn(move || {
        run_tts_loop(
            session_id,
            sentences,
            start_sentence,
            start_word,
            rate_handle,
            engine,
            voice,
            cancel_flag,
            finished_flag,
        );
    });

    Ok(())
}

#[cfg(feature = "native-audio")]
fn pause_tts(session_id: usize) -> Result<()> {
    stop_tts(session_id, false)
}

#[cfg(feature = "native-audio")]
fn stop_tts(session_id: usize, reset_word: bool) -> Result<()> {
    let flags = READER_SESSIONS.with(|sessions| {
        let mut map = sessions.borrow_mut();
        if let Some(session) = map.get_mut(&session_id) {
            if let Some(tts) = session.tts.as_ref() {
                Some((tts.cancel.clone(), tts.finished.clone()))
            } else {
                None
            }
        } else {
            None
        }
    });

    if let Some((cancel, finished)) = flags {
        cancel.store(true, Ordering::SeqCst);
        for _ in 0..200 {
            if finished.load(Ordering::SeqCst) {
                break;
            }
            thread::sleep(Duration::from_millis(20));
        }
        finalize_tts(session_id);
    }

    if reset_word {
        set_active_word(session_id, 0, true)?;
    }

    Ok(())
}

#[cfg(feature = "native-audio")]
fn run_tts_loop(
    session_id: usize,
    sentences: Vec<SentenceData>,
    start_sentence: usize,
    start_word: usize,
    rate_handle: Arc<AtomicU32>,
    engine: Arc<dyn tts::SpeechEngine>,
    voice: Option<String>,
    cancel: Arc<AtomicBool>,
    finished: Arc<AtomicBool>,
) {
    let (stream, handle) = match OutputStream::try_default() {
        Ok(values) => values,
        Err(err) => {
            tracing::error!(?err, "failed to initialize audio output for TTS");
            finished.store(true, Ordering::SeqCst);
            slint::invoke_from_event_loop(move || finalize_tts(session_id)).ok();
            return;
        }
    };

    let sink = match Sink::try_new(&handle) {
        Ok(sink) => sink,
        Err(err) => {
            tracing::error!(?err, "failed to open audio sink for TTS");
            finished.store(true, Ordering::SeqCst);
            slint::invoke_from_event_loop(move || finalize_tts(session_id)).ok();
            return;
        }
    };

    let voice_ref = voice.as_deref();

    'sentences: for (sentence_index, sentence) in sentences.iter().enumerate().skip(start_sentence) {
        if cancel.load(Ordering::SeqCst) {
            break;
        }

        let _ = slint::invoke_from_event_loop(move || {
            let _ = set_sentence(session_id, sentence_index, 0, true);
        });

        let stored_rate = {
            let raw = rate_handle.load(Ordering::SeqCst);
            if raw == 0 {
                rate_to_atomic(DEFAULT_TTS_RATE)
            } else {
                raw
            }
        };
        let current_rate = atomic_to_rate(stored_rate);

        let synth_options = SynthesisOptions {
            rate: current_rate,
            voice: voice_ref,
        };

        let audio = match engine.synthesize(&sentence.text, &synth_options) {
            Ok(chunk) => chunk,
            Err(err) => {
                tracing::error!(?err, "TTS synthesis failed");
                sink.stop();
                break;
            }
        };

        let channel_count = audio.channels.max(1);
        let sample_rate = audio.sample_rate.max(1);
        let total_samples = audio.samples.len();
        let frames = if channel_count as usize == 0 {
            0
        } else {
            total_samples / channel_count as usize
        };
        let sentence_secs = if sample_rate == 0 {
            0.0
        } else {
            frames as f32 / sample_rate as f32
        };
        let audio_duration = if sentence_secs > 0.0 {
            Duration::from_secs_f32(sentence_secs)
        } else {
            Duration::from_millis(FALLBACK_WORD_MS * sentence.words.len().max(1) as u64)
        };

        let buffer = SamplesBuffer::new(channel_count, sample_rate, audio.samples);
        sink.append(buffer);

        let start_word_idx = if sentence.words.is_empty() {
            0
        } else if sentence_index == start_sentence {
            start_word.min(sentence.words.len() - 1)
        } else {
            0
        };

        if sentence.words.is_empty() {
            let wait_duration = if audio_duration.is_zero() {
                scaled_duration(FALLBACK_WORD_MS, current_rate)
            } else {
                audio_duration
            };

            if !sleep_with_cancel(wait_duration, &cancel) {
                sink.stop();
                break;
            }
            continue;
        }

        let weights = compute_word_weights(&sentence.words);
        let mut remaining_weight: usize = weights[start_word_idx..]
            .iter()
            .copied()
            .sum::<usize>()
            .max(1);
        let mut remaining_time = audio_duration;

        for word_index in start_word_idx..sentence.words.len() {
            if cancel.load(Ordering::SeqCst) {
                break 'sentences;
            }

            let _ = slint::invoke_from_event_loop(move || {
                let _ = set_active_word(session_id, word_index, false);
            });

            let weight = weights[word_index].max(1);
            let share = (weight as f32) / (remaining_weight as f32);
            let mut word_duration = if sentence_secs > 0.0 {
                Duration::from_secs_f32(sentence_secs * share)
            } else {
                let base = (FALLBACK_WORD_MS as f32 * share.max(0.1)).round() as u64;
                scaled_duration(base.max(1), current_rate)
            };

            if word_duration.is_zero() {
                word_duration = Duration::from_millis(MIN_HIGHLIGHT_STEP_MS);
            }

            if word_duration > remaining_time {
                word_duration = remaining_time;
            }

            if !sleep_with_cancel(word_duration, &cancel) {
                sink.stop();
                break 'sentences;
            }

            remaining_weight = remaining_weight.saturating_sub(weight);
            remaining_time = remaining_time.saturating_sub(word_duration);
        }

        if cancel.load(Ordering::SeqCst) {
            sink.stop();
            break;
        }

        if !remaining_time.is_zero() {
            if !sleep_with_cancel(remaining_time, &cancel) {
                sink.stop();
                break;
            }
        }
    }

    sink.sleep_until_end();
    drop(sink);
    drop(stream);
    finished.store(true, Ordering::SeqCst);
    slint::invoke_from_event_loop(move || finalize_tts(session_id)).ok();
}

#[cfg(feature = "native-audio")]
fn compute_word_weights(words: &[String]) -> Vec<usize> {
    words
        .iter()
        .map(|w| {
            let weight = w.chars().filter(|c| c.is_alphanumeric()).count();
            weight.max(1)
        })
        .collect()
}

#[cfg(feature = "native-audio")]
fn sleep_with_cancel(duration: Duration, cancel: &AtomicBool) -> bool {
    if duration.is_zero() {
        return true;
    }

    let mut elapsed = Duration::ZERO;
    let step = Duration::from_millis(MIN_HIGHLIGHT_STEP_MS);

    while elapsed < duration {
        if cancel.load(Ordering::SeqCst) {
            return false;
        }
        let remaining = duration.saturating_sub(elapsed);
        let sleep_for = if remaining < step { remaining } else { step };
        if sleep_for.is_zero() {
            break;
        }
        thread::sleep(sleep_for);
        elapsed += sleep_for;
    }

    true
}

#[cfg(feature = "native-audio")]
fn rate_to_atomic(rate: f32) -> u32 {
    let scaled = (rate.clamp(TTS_MIN_RATE, TTS_MAX_RATE) * 1000.0).round();
    let min_scaled = (TTS_MIN_RATE * 1000.0).round();
    let max_scaled = (TTS_MAX_RATE * 1000.0).round();
    scaled.clamp(min_scaled, max_scaled) as u32
}

#[cfg(feature = "native-audio")]
fn atomic_to_rate(value: u32) -> f32 {
    (value as f32) / 1000.0
}

#[cfg(feature = "native-audio")]
fn scaled_duration(base_ms: u64, rate: f32) -> Duration {
    let adjusted = if rate <= 0.05 { base_ms } else { (base_ms as f32 / rate).round() as u64 };
    let clamped = adjusted.clamp(1, 10_000);
    Duration::from_millis(clamped)
}

#[cfg(feature = "native-audio")]
fn finalize_tts(session_id: usize) {
    READER_SESSIONS.with(|sessions| {
        let mut map = sessions.borrow_mut();
        if let Some(session) = map.get_mut(&session_id) {
            session.tts = None;
            let _ = save_progress(
                &session.book_id,
                session.current_sentence,
                session.current_word,
            );
            if let Some(window) = session.window.upgrade() {
                if session.sentences.is_empty() {
                    window.set_active_word_index(-1);
                } else {
                    let word_count = session.sentences[session.current_sentence].words.len();
                    if word_count == 0 {
                        window.set_active_word_index(-1);
                    } else {
                        window
                            .set_active_word_index(session.current_word.min(word_count - 1) as i32);
                    }
                }
            }
        }
    });
}

#[cfg(feature = "native-audio")]
async fn create_backend() -> Result<(RodioBackend, rodio::OutputStream)> {
    RodioBackend::new().context("failed to initialize audio backend")
}

#[cfg(not(feature = "native-audio"))]
async fn create_backend() -> Result<NullBackend> {
    Ok(NullBackend)
}

#[cfg(feature = "native-audio")]
struct RodioBackend {
    handle: rodio::OutputStreamHandle,
    inner: Arc<parking_lot::Mutex<Option<RodioState>>>,
}

#[cfg(feature = "native-audio")]
impl Clone for RodioBackend {
    fn clone(&self) -> Self {
        Self {
            handle: self.handle.clone(),
            inner: Arc::clone(&self.inner),
        }
    }
}

#[cfg(feature = "native-audio")]
struct RodioState {
    sink: rodio::Sink,
    started_at: Option<Instant>,
    accumulated: Duration,
}

#[cfg(feature = "native-audio")]
impl RodioBackend {
    fn new() -> Result<(Self, rodio::OutputStream)> {
        let (stream, handle) = rodio::OutputStream::try_default()?;
        Ok((
            Self {
                handle,
                inner: Arc::new(parking_lot::Mutex::new(None)),
            },
            stream,
        ))
    }
}

#[cfg(feature = "native-audio")]
#[async_trait::async_trait]
impl ebook_core::playback::AudioBackend for RodioBackend {
    async fn load(&self, chapter: &ebook_core::AudioChapter) -> Result<()> {
        let path = chapter.file.clone();
        let handle = self.handle.clone();
        let inner = self.inner.clone();
        tokio::task::spawn_blocking(move || {
            let file = std::fs::File::open(&path)?;
            let source = rodio::Decoder::new(std::io::BufReader::new(file))?;
            let sink = rodio::Sink::try_new(&handle)?;
            sink.pause();
            sink.append(source);
            sink.pause();
            let mut guard = inner.lock();
            *guard = Some(RodioState {
                sink,
                started_at: None,
                accumulated: Duration::ZERO,
            });
            Result::<_, anyhow::Error>::Ok(())
        })
        .await??;
        Ok(())
    }

    async fn play(&self) -> Result<()> {
        let inner = self.inner.clone();
        tokio::task::spawn_blocking(move || {
            let mut guard = inner.lock();
            if let Some(state) = guard.as_mut() {
                state.sink.play();
                if state.started_at.is_none() {
                    state.started_at = Some(Instant::now());
                }
            }
            Result::<_, anyhow::Error>::Ok(())
        })
        .await??;
        Ok(())
    }

    async fn pause(&self) -> Result<()> {
        let inner = self.inner.clone();
        tokio::task::spawn_blocking(move || {
            let mut guard = inner.lock();
            if let Some(state) = guard.as_mut() {
                state.sink.pause();
                if let Some(started_at) = state.started_at.take() {
                    state.accumulated += started_at.elapsed();
                }
            }
            Result::<_, anyhow::Error>::Ok(())
        })
        .await??;
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        let inner = self.inner.clone();
        tokio::task::spawn_blocking(move || {
            let mut guard = inner.lock();
            if let Some(state) = guard.as_mut() {
                state.sink.stop();
            }
            *guard = None;
            Result::<_, anyhow::Error>::Ok(())
        })
        .await??;
        Ok(())
    }

    async fn seek(&self, _position: Duration) -> Result<()> {
        // rodio sink does not support precise seek; placeholder for future backend enhancements
        Ok(())
    }

    async fn position(&self) -> Result<Duration> {
        let inner = self.inner.clone();
        Ok(tokio::task::spawn_blocking(move || {
            let guard = inner.lock();
            guard
                .as_ref()
                .map(|state| {
                    let mut elapsed = state.accumulated;
                    if let Some(started_at) = state.started_at {
                        elapsed += started_at.elapsed();
                    }
                    elapsed
                })
                .unwrap_or_default()
        })
        .await?)
    }
}

#[cfg(not(feature = "native-audio"))]
#[derive(Clone, Default)]
struct NullBackend;

#[cfg(not(feature = "native-audio"))]
#[async_trait::async_trait]
impl ebook_core::playback::AudioBackend for NullBackend {
    async fn load(&self, _chapter: &ebook_core::AudioChapter) -> Result<()> {
        Ok(())
    }

    async fn play(&self) -> Result<()> {
        Ok(())
    }

    async fn pause(&self) -> Result<()> {
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        Ok(())
    }

    async fn seek(&self, _position: Duration) -> Result<()> {
        Ok(())
    }

    async fn position(&self) -> Result<Duration> {
        Ok(Duration::ZERO)
    }
}
