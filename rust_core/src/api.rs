use std::thread;
use std::time::Duration;

#[cfg(not(feature = "bridge"))]
use std::marker::PhantomData;

use anyhow::anyhow;
use once_cell::sync::Lazy;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::engine::{AudioFrame, EngineRegistryHandle};

#[cfg(feature = "bridge")]
use flutter_rust_bridge::frb;

#[cfg(feature = "bridge")]
type StreamSink<T> = crate::StreamSink<T>;

#[cfg(not(feature = "bridge"))]
#[derive(Clone, Default)]
pub struct StreamSink<T> {
    _phantom: PhantomData<T>,
}

#[cfg(not(feature = "bridge"))]
impl<T> StreamSink<T> {
    pub fn add(&self, _value: T) -> Result<(), ()> {
        Ok(())
    }

    pub fn add_error<E>(&self, _value: E) -> Result<(), ()> {
        Ok(())
    }

    pub fn close(&self) -> Result<(), ()> {
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TtsState {
    pub is_playing: bool,
    pub current_model: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioChunk {
    pub pcm: Vec<i16>,
    pub sample_rate: u32,
    pub start_text_idx: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngineRequest {
    pub backend: EngineBackend,
    #[serde(default)]
    pub gain_db: Option<f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EngineBackend {
    Auto { model_path: String },
    Piper(PiperBackendConfig),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PiperBackendConfig {
    pub model_path: String,
    #[serde(default)]
    pub config_path: Option<String>,
    #[serde(default)]
    pub speaker: Option<String>,
    #[serde(default)]
    pub sample_rate: Option<u32>,
}

static ENGINE_REGISTRY: Lazy<RwLock<Option<EngineRegistryHandle>>> =
    Lazy::new(|| RwLock::new(None));

pub fn init_registry(handle: EngineRegistryHandle) {
    *ENGINE_REGISTRY.write() = Some(handle);
}

#[cfg_attr(feature = "bridge", frb)]
pub fn bootstrap_default_engine() {
    if ENGINE_REGISTRY.read().is_none() {
        init_registry(EngineRegistryHandle::default());
    }
}

#[cfg_attr(feature = "bridge", frb)]
pub fn current_state() -> TtsState {
    let registry = ENGINE_REGISTRY.read();
    let model = registry
        .as_ref()
        .and_then(|handle| handle.active_model())
        .unwrap_or_else(|| "unloaded".to_string());
    TtsState {
        is_playing: false,
        current_model: model,
    }
}

#[cfg_attr(feature = "bridge", frb)]
pub fn stream_audio(text: String, request: EngineRequest, sink: StreamSink<AudioChunk>) {
    let maybe_registry = ENGINE_REGISTRY.read().clone();
    let Some(handle) = maybe_registry else {
        let _ = sink.add_error(anyhow!("engine registry not initialized").to_string());
        return;
    };
    let model_path = backend_model_path(&request.backend).to_string();

    info!(%model_path, "spawning synthesis thread");
    thread::spawn(move || match handle.load_model(&model_path) {
        Ok(engine) => match engine.synthesize(&text) {
            Ok(frames) => dispatch_frames(frames, sink),
            Err(err) => {
                let _ = sink.add_error(anyhow!(err).to_string());
            }
        },
        Err(err) => {
            let _ = sink.add_error(anyhow!(err).to_string());
        }
    });
}

fn dispatch_frames(frames: Vec<AudioFrame>, sink: StreamSink<AudioChunk>) {
    for frame in frames {
        let chunk = AudioChunk {
            pcm: frame.samples,
            sample_rate: frame.sample_rate,
            start_text_idx: frame.associated_text_idx,
        };
        if sink.add(chunk).is_err() {
            return;
        }
        thread::sleep(Duration::from_millis(50));
    }
}

fn backend_model_path(backend: &EngineBackend) -> &str {
    match backend {
        EngineBackend::Auto { model_path } => model_path,
        EngineBackend::Piper(config) => &config.model_path,
    }
}
