use std::f32::consts::PI;
use std::sync::Arc;

use parking_lot::RwLock;
use thiserror::Error;

#[cfg(all(feature = "piper", not(target_os = "windows")))]
use crate::api::PiperBackendConfig;

#[cfg(all(feature = "piper", not(target_os = "windows")))]
pub mod piper;

#[derive(Debug, Clone)]
pub struct AudioFrame {
    pub samples: Vec<i16>,
    pub sample_rate: u32,
    pub associated_text_idx: usize,
}

pub trait TTSEngine: Send + Sync + 'static {
    fn synthesize(&self, text: &str) -> std::result::Result<Vec<AudioFrame>, String>;
}

#[derive(Debug, Error)]
pub enum RegistryError {
    #[error("piper backend not compiled in this build")]
    PiperUnavailable,
    #[error("model load failed: {0}")]
    LoadFailed(String),
}

pub struct EngineRegistryHandle {
    mock_engine: Arc<MockEngine>,
    #[cfg(all(feature = "piper", not(target_os = "windows")))]
    piper_engine: Arc<RwLock<Option<CachedPiperEngine>>>,
    active_model: Arc<RwLock<Option<String>>>,
}

impl Clone for EngineRegistryHandle {
    fn clone(&self) -> Self {
        Self {
            mock_engine: Arc::clone(&self.mock_engine),
            #[cfg(all(feature = "piper", not(target_os = "windows")))]
            piper_engine: Arc::clone(&self.piper_engine),
            active_model: Arc::clone(&self.active_model),
        }
    }
}

impl EngineRegistryHandle {
    pub fn new() -> Self {
        Self {
            mock_engine: Arc::new(MockEngine::default()),
            #[cfg(all(feature = "piper", not(target_os = "windows")))]
            piper_engine: Arc::new(RwLock::new(None)),
            active_model: Arc::new(RwLock::new(None)),
        }
    }

    pub fn active_model(&self) -> Option<String> {
        self.active_model.read().clone()
    }

    pub fn mock_engine(&self, label: &str) -> Arc<dyn TTSEngine> {
        self.mock_engine.set_last_model(label);
        *self.active_model.write() = Some(label.to_string());
        self.mock_engine.clone()
    }

    #[cfg(all(feature = "piper", not(target_os = "windows")))]
    pub fn load_piper(
        &self,
        config: &PiperBackendConfig,
    ) -> Result<Arc<dyn TTSEngine>, RegistryError> {
        use piper::PiperEngine;

        let fingerprint = format!(
            "{}::{}::{}",
            config.model_path,
            config
                .config_path
                .as_deref()
                .unwrap_or(config.model_path.as_str()),
            config.speaker.as_deref().unwrap_or("default")
        );

        if let Some(cache) = self.piper_engine.read().clone() {
            if cache.fingerprint == fingerprint {
                *self.active_model.write() = Some(config.model_path.clone());
                return Ok(cache.engine);
            }
        }

        let engine = PiperEngine::new(config).map_err(RegistryError::LoadFailed)?;
        let arc_engine: Arc<dyn TTSEngine> = Arc::new(engine);
        *self.piper_engine.write() = Some(CachedPiperEngine {
            fingerprint,
            engine: arc_engine.clone(),
        });
        *self.active_model.write() = Some(config.model_path.clone());
        Ok(arc_engine)
    }
}

impl Default for EngineRegistryHandle {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(all(feature = "piper", not(target_os = "windows")))]
#[derive(Clone)]
struct CachedPiperEngine {
    fingerprint: String,
    engine: Arc<dyn TTSEngine>,
}

#[derive(Default, Clone)]
struct MockEngine {
    last_model: Arc<RwLock<Option<String>>>,
}

impl MockEngine {
    fn set_last_model(&self, label: &str) {
        *self.last_model.write() = Some(label.to_string());
    }
}

impl TTSEngine for MockEngine {
    fn synthesize(&self, text: &str) -> std::result::Result<Vec<AudioFrame>, String> {
        let sample_rate = 16_000u32;
        let mut pcm = Vec::new();
        let mut words: Vec<&str> = text
            .split_whitespace()
            .filter(|token| !token.is_empty())
            .collect();
        if words.is_empty() {
            words = vec!["..."];
        }
        for (idx, _word) in words.iter().enumerate() {
            let freq = 220.0 + ((idx % 12) as f32 * 15.0);
            let duration_samples = (sample_rate as f32 * 0.28) as usize;
            for n in 0..duration_samples {
                let t = n as f32 / sample_rate as f32;
                let envelope = 0.5
                    - 0.5 * (2.0 * PI * t / (duration_samples as f32 / sample_rate as f32)).cos();
                let sample =
                    (envelope * (freq * 2.0 * PI * t).sin() * i16::MAX as f32 * 0.1) as i16;
                pcm.push(sample);
            }
            // brief silence between words
            pcm.extend(std::iter::repeat(0).take((sample_rate as f32 * 0.05) as usize));
        }
        if pcm.is_empty() {
            pcm.resize(800, 0);
        }
        Ok(chunk_audio_samples(pcm, sample_rate, text.len()))
    }
}

pub fn chunk_audio_samples(
    samples: Vec<i16>,
    sample_rate: u32,
    text_len: usize,
) -> Vec<AudioFrame> {
    if samples.is_empty() {
        return vec![AudioFrame {
            samples,
            sample_rate,
            associated_text_idx: 0,
        }];
    }

    let chunk_samples = ((sample_rate as usize * 200) / 1000).max(1);
    let total_samples = samples.len();
    let mut frames = Vec::new();
    let mut offset = 0usize;

    while offset < total_samples {
        let end = (offset + chunk_samples).min(total_samples);
        let chunk = samples[offset..end].to_vec();
        let ratio = if total_samples == 0 {
            0.0
        } else {
            offset as f64 / total_samples as f64
        };
        let start_idx = (ratio * text_len as f64) as usize;
        frames.push(AudioFrame {
            samples: chunk,
            sample_rate,
            associated_text_idx: start_idx,
        });
        offset = end;
    }

    frames
}
