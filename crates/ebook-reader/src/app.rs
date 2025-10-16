use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;
use std::time::Duration;

#[cfg(feature = "native-audio")]
use std::time::Instant;

use anyhow::{Context, Result};
use ebook_core::{
    library::{LibraryConfig, LibraryLoader},
    playback::{PlaybackCommand, PlaybackController, PlaybackEvent},
    text::{load_text_sections, TextSection},
    Ebook,
};
use slint::{SharedString, VecModel};
use tokio::runtime::{Handle, Runtime};
use tokio::sync::mpsc::Receiver;

slint::include_modules!();

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
        if let Some(window) = window_handle.upgrade() {
            window.set_status_text(SharedString::from("Opening reader…"));
        }
        let books = Arc::clone(&books);
        let handle = handle.clone();
        let window_noti = window_handle.clone();
        handle.spawn(async move {
            let Some(book) = books.get(index as usize).cloned() else {
                notify_status(window_noti.clone(), "Book could not be found");
                return;
            };
            let Some(text_content) = book.text_content.clone() else {
                notify_status(
                    window_noti.clone(),
                    format!("{} has no readable text.", book.title),
                );
                return;
            };

            match tokio::task::spawn_blocking(move || load_text_sections(&text_content)).await {
                Ok(Ok(sections)) => {
                    let status_handle = window_noti.clone();
                    slint::invoke_from_event_loop(move || {
                        if let Err(err) = show_reader_window(book, sections) {
                            if let Some(window) = status_handle.upgrade() {
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
                    notify_status(window_noti, format!("Failed to load text: {err:#}"));
                }
                Err(err) => {
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
    let chapters_model = Rc::new(VecModel::from(chapter_items));
    reader.set_chapters(chapters_model.clone().into());
    let _ = reader.set_selected_index(0);

    let sections = Rc::new(sections);
    if let Some(first) = sections.get(0) {
        reader.set_chapter_title(SharedString::from(first.title.clone()));
        reader.set_content(SharedString::from(first.body.clone()));
    }

    let reader_weak = reader.as_weak();
    let sections_for_callback = Rc::clone(&sections);
    reader.on_chapter_selected(move |idx| {
        if let (Some(section), Some(window)) = (
            sections_for_callback.get(idx as usize),
            reader_weak.upgrade(),
        ) {
            let _ = window.set_selected_index(idx);
            window.set_chapter_title(SharedString::from(section.title.clone()));
            window.set_content(SharedString::from(section.body.clone()));
        }
    });

    let reader_weak = reader.as_weak();
    reader.on_request_close(move || {
        if let Some(window) = reader_weak.upgrade() {
            let _ = window.hide();
        }
    });

    reader.show()?;
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
