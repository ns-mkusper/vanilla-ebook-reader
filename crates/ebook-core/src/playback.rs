use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, Result};
use async_trait::async_trait;
use parking_lot::RwLock;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tracing::{error, instrument};

use crate::model::Chapter;

const PLAYBACK_CHANNEL_BUFFER: usize = 8;

#[derive(Debug, Clone)]
pub struct PlaybackState {
    inner: Arc<RwLock<StateInner>>,
}

#[derive(Debug, Default)]
struct StateInner {
    current_chapter: Option<Chapter>,
    is_playing: bool,
    position: Duration,
}

impl PlaybackState {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(RwLock::new(StateInner::default())),
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        let inner = self.inner.read();
        Snapshot {
            current_chapter: inner.current_chapter.clone(),
            is_playing: inner.is_playing,
            position: inner.position,
        }
    }

    fn set_chapter(&self, chapter: Option<Chapter>) {
        let mut inner = self.inner.write();
        inner.current_chapter = chapter;
        if inner.current_chapter.is_none() {
            inner.is_playing = false;
            inner.position = Duration::ZERO;
        }
    }

    fn set_playing(&self, playing: bool) {
        self.inner.write().is_playing = playing;
    }

    fn set_position(&self, position: Duration) {
        self.inner.write().position = position;
    }
}

#[derive(Debug, Clone)]
pub struct Snapshot {
    pub current_chapter: Option<Chapter>,
    pub is_playing: bool,
    pub position: Duration,
}

#[derive(Debug)]
pub enum PlaybackCommand {
    LoadAndPlay(Chapter),
    Pause,
    Resume,
    Stop,
    Seek(Duration),
}

#[derive(Debug)]
pub enum PlaybackEvent {
    ChapterStarted(Chapter),
    ChapterComplete(Chapter),
    ChapterFailed {
        chapter: Chapter,
        error: anyhow::Error,
    },
}

#[async_trait]
pub trait AudioBackend: Send + Sync + 'static {
    async fn load(&self, chapter: &Chapter) -> Result<()>;
    async fn play(&self) -> Result<()>;
    async fn pause(&self) -> Result<()>;
    async fn stop(&self) -> Result<()>;
    async fn seek(&self, position: Duration) -> Result<()>;
    async fn position(&self) -> Result<Duration>;
}

pub struct PlaybackController {
    commands: mpsc::Sender<PlaybackCommand>,
    #[allow(dead_code)]
    worker: JoinHandle<()>,
    state: PlaybackState,
}

impl PlaybackController {
    pub fn new<B: AudioBackend>(backend: B) -> (Self, mpsc::Receiver<PlaybackEvent>) {
        let (cmd_tx, mut cmd_rx) = mpsc::channel(PLAYBACK_CHANNEL_BUFFER);
        let (evt_tx, evt_rx) = mpsc::channel(PLAYBACK_CHANNEL_BUFFER);
        let state = PlaybackState::new();
        let state_clone = state.clone();

        let worker = tokio::spawn(async move {
            while let Some(cmd) = cmd_rx.recv().await {
                match handle_command(cmd, &backend, &evt_tx, &state_clone).await {
                    Ok(_) => {}
                    Err(err) => error!(?err, "playback command failed"),
                }
            }
        });

        (
            Self {
                commands: cmd_tx,
                worker,
                state,
            },
            evt_rx,
        )
    }

    pub fn state(&self) -> PlaybackState {
        self.state.clone()
    }

    pub fn command_sender(&self) -> mpsc::Sender<PlaybackCommand> {
        self.commands.clone()
    }

    pub async fn send(&self, command: PlaybackCommand) -> Result<()> {
        self.commands
            .send(command)
            .await
            .map_err(|_| anyhow!("playback command channel closed"))
    }
}

#[instrument(skip(backend, evt_tx, state))]
async fn handle_command<B: AudioBackend>(
    command: PlaybackCommand,
    backend: &B,
    evt_tx: &mpsc::Sender<PlaybackEvent>,
    state: &PlaybackState,
) -> Result<()> {
    match command {
        PlaybackCommand::LoadAndPlay(chapter) => {
            backend.load(&chapter).await?;
            backend.play().await?;
            state.set_chapter(Some(chapter.clone()));
            state.set_playing(true);
            let _ = evt_tx.send(PlaybackEvent::ChapterStarted(chapter)).await;
        }
        PlaybackCommand::Pause => {
            backend.pause().await?;
            state.set_playing(false);
        }
        PlaybackCommand::Resume => {
            backend.play().await?;
            state.set_playing(true);
        }
        PlaybackCommand::Stop => {
            backend.stop().await?;
            if let Some(chapter) = state.snapshot().current_chapter {
                let _ = evt_tx.send(PlaybackEvent::ChapterComplete(chapter)).await;
            }
            state.set_chapter(None);
        }
        PlaybackCommand::Seek(position) => {
            backend.seek(position).await?;
            state.set_position(position);
        }
    }
    if let Ok(position) = backend.position().await {
        state.set_position(position);
    }
    Ok(())
}

pub mod serde_duration {
    use std::time::Duration;

    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(value: &Duration, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_u64(value.as_secs())
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Duration, D::Error> {
        let secs = u64::deserialize(deserializer)?;
        Ok(Duration::from_secs(secs))
    }

    pub mod option {
        use std::time::Duration;

        use serde::{Deserialize, Deserializer, Serializer};

        pub fn serialize<S: Serializer>(
            value: &Option<Duration>,
            serializer: S,
        ) -> Result<S::Ok, S::Error> {
            match value {
                Some(duration) => serializer.serialize_some(&duration.as_secs()),
                None => serializer.serialize_none(),
            }
        }

        pub fn deserialize<'de, D: Deserializer<'de>>(
            deserializer: D,
        ) -> Result<Option<Duration>, D::Error> {
            Option::<u64>::deserialize(deserializer).map(|opt| opt.map(Duration::from_secs))
        }
    }
}
