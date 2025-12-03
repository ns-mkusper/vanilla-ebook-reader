use std::sync::Arc;

pub mod piper;

use parking_lot::RwLock;
use thiserror::Error;

#[derive(Debug, Clone)]
pub struct AudioFrame {
    pub samples: Vec<i16>,
    pub sample_rate: u32,
    pub associated_text_idx: usize,
}

pub trait TTSEngine: Send + Sync + 'static {
    fn load_model(&mut self, path: &str) -> std::result::Result<(), String>;
    fn synthesize(&self, text: &str) -> std::result::Result<Vec<AudioFrame>, String>;
}

#[derive(Debug, Error)]
pub enum RegistryError {
    #[error("no engine factory registered")]
    NoFactory,
    #[error("model load failed: {0}")]
    LoadFailed(String),
}

pub struct EngineRegistryHandle {
    factory: Arc<dyn Fn() -> Box<dyn TTSEngine> + Send + Sync>,
    active_model: Arc<RwLock<Option<String>>>,
}

impl Clone for EngineRegistryHandle {
    fn clone(&self) -> Self {
        Self {
            factory: Arc::clone(&self.factory),
            active_model: Arc::clone(&self.active_model),
        }
    }
}

impl EngineRegistryHandle {
    pub fn new_with_factory<F, E>(factory: F) -> Self
    where
        F: Fn() -> E + Send + Sync + 'static,
        E: TTSEngine,
    {
        let factory = Arc::new(move || Box::new(factory()) as Box<dyn TTSEngine>);
        Self {
            factory,
            active_model: Arc::new(RwLock::new(None)),
        }
    }

    pub fn active_model(&self) -> Option<String> {
        self.active_model.read().clone()
    }

    pub fn load_model(&self, model_path: &str) -> std::result::Result<Arc<dyn TTSEngine>, String> {
        let mut engine = (self.factory)();
        engine.load_model(model_path)?;
        *self.active_model.write() = Some(model_path.to_string());
        Ok(Arc::from(engine))
    }
}

impl Default for EngineRegistryHandle {
    fn default() -> Self {
        Self::new_with_factory(MockEngine::default)
    }
}

#[derive(Default, Clone)]
struct MockEngine {
    model_path: Arc<RwLock<Option<String>>>,
}

impl TTSEngine for MockEngine {
    fn load_model(&mut self, path: &str) -> std::result::Result<(), String> {
        *self.model_path.write() = Some(path.to_string());
        Ok(())
    }

    fn synthesize(&self, text: &str) -> std::result::Result<Vec<AudioFrame>, String> {
        let sample_rate = 16_000u32;
        let mut frames = Vec::new();
        for (idx, ch) in text.char_indices() {
            let amplitude = (ch as i32 % 32) as i16;
            let samples = vec![amplitude; (sample_rate as f32 * 0.05) as usize];
            frames.push(AudioFrame {
                samples,
                sample_rate,
                associated_text_idx: idx,
            });
        }
        if frames.is_empty() {
            frames.push(AudioFrame {
                samples: vec![0; 800],
                sample_rate,
                associated_text_idx: 0,
            });
        }
        Ok(frames)
    }
}
