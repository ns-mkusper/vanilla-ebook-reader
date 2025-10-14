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
    let (controller, events) = runtime.block_on(async {
        let backend = create_backend().await?;
        Ok::<_, anyhow::Error>(PlaybackController::new(backend))
    })?;

    let window = MainWindow::new().context("failed to create MainWindow")?;
    window.set_status_text(SharedString::from("Ready"));

    populate_ui(&window, &books);

    wire_play_handler(&window, &books, controller.command_sender(), handle.clone());
    spawn_event_listener(window.as_weak(), events, handle);

    let _ = window.run();
    Ok(())
}

fn populate_ui(window: &MainWindow, books: &Arc<Vec<Ebook>>) {
    let items: Vec<_> = books
        .iter()
        .map(|book| EbookItem {
            title: SharedString::from(book.title.clone()),
            author: SharedString::from(book.author.clone().unwrap_or_else(|| "Unknown".into())),
            duration: SharedString::from(format_duration(book.total_duration())),
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
            window.set_status_text(SharedString::from("Loading…"));
        }
        let sender = sender.clone();
        let books = Arc::clone(&books);
        let handle = handle.clone();
        handle.spawn(async move {
            if let Some(book) = books.get(index as usize).cloned() {
                if let Some(chapter) = book.chapters.first().cloned() {
                    if let Err(err) = sender.send(PlaybackCommand::LoadAndPlay(chapter)).await {
                        tracing::warn!(?err, "failed to send playback command");
                    }
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

#[cfg(feature = "native-audio")]
async fn create_backend() -> Result<RodioBackend> {
    RodioBackend::new().context("failed to initialize audio backend")
}

#[cfg(not(feature = "native-audio"))]
async fn create_backend() -> Result<NullBackend> {
    Ok(NullBackend::default())
}

#[cfg(feature = "native-audio")]
#[derive(Clone)]
struct RodioBackend {
    _stream: rodio::OutputStream,
    handle: rodio::OutputStreamHandle,
    inner: Arc<parking_lot::Mutex<Option<RodioState>>>,
}

#[cfg(feature = "native-audio")]
struct RodioState {
    sink: rodio::Sink,
    started_at: Option<Instant>,
    accumulated: Duration,
}

#[cfg(feature = "native-audio")]
impl RodioBackend {
    fn new() -> Result<Self> {
        let (stream, handle) = rodio::OutputStream::try_default()?;
        Ok(Self {
            _stream: stream,
            handle,
            inner: Arc::new(parking_lot::Mutex::new(None)),
        })
    }
}

#[cfg(feature = "native-audio")]
#[async_trait::async_trait]
impl ebook_core::playback::AudioBackend for RodioBackend {
    async fn load(&self, chapter: &ebook_core::Chapter) -> Result<()> {
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
    async fn load(&self, _chapter: &ebook_core::Chapter) -> Result<()> {
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
