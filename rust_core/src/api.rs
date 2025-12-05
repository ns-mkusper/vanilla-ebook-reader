use std::sync::{Arc, Once};
use std::thread;
use std::time::Duration;

#[cfg(not(feature = "bridge"))]
use std::marker::PhantomData;

use anyhow::anyhow;
use once_cell::sync::Lazy;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::engine::{AudioFrame, EngineRegistryHandle, RegistryError, TTSEngine};

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
static TRACING_INIT: Once = Once::new();

pub fn init_registry(handle: EngineRegistryHandle) {
    *ENGINE_REGISTRY.write() = Some(handle);
}

#[cfg_attr(feature = "bridge", frb)]
pub fn init_tracing(filter: Option<String>) {
    let env_filter = filter
        .or_else(|| std::env::var("RUST_LOG").ok())
        .unwrap_or_else(|| "rust_core=info,piper_rs=info,ort=warn".to_string());

    TRACING_INIT.call_once(move || {
        #[cfg(target_os = "android")]
        {
            use android_logger::Config;
            android_logger::init_once(
                Config::default()
                    .with_max_level(log::LevelFilter::Trace)
                    .with_tag("rust_core"),
            );
        }

        let _ = tracing_log::LogTracer::init();
        let subscriber = tracing_subscriber::fmt()
            .with_env_filter(env_filter)
            .with_target(true)
            .with_ansi(cfg!(not(target_os = "android")))
            .without_time()
            .finish();

        let _ = tracing::subscriber::set_global_default(subscriber);
    });
}

#[cfg_attr(feature = "bridge", frb)]
pub fn bootstrap_default_engine() {
    init_tracing(None);
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
    let backend = request.backend.clone();
    let model_path = backend_model_path(&backend).to_string();

    info!(%model_path, "spawning synthesis thread");
    thread::spawn(move || match resolve_engine(&handle, &backend) {
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

fn resolve_engine(
    handle: &EngineRegistryHandle,
    backend: &EngineBackend,
) -> Result<Arc<dyn TTSEngine>, RegistryError> {
    match backend {
        EngineBackend::Auto { model_path } => Ok(handle.mock_engine(model_path)),
        EngineBackend::Piper(config) => {
            #[cfg(all(feature = "piper", not(target_os = "windows")))]
            {
                handle.load_piper(config)
            }
            #[cfg(not(all(feature = "piper", not(target_os = "windows"))))]
            {
                let _ = config;
                Err(RegistryError::PiperUnavailable)
            }
        }
    }
}
