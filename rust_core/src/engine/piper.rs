//! Piper ONNX-backed engine implementation.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::api::PiperBackendConfig;
use crate::engine::{chunk_audio_samples, AudioFrame, TTSEngine};

#[cfg(feature = "piper")]
use piper_rs::synth::PiperSpeechSynthesizer;

#[cfg_attr(feature = "bridge", flutter_rust_bridge::frb(opaque))]
pub struct PiperEngine {
    synthesizer: Arc<PiperSpeechSynthesizer>,
    sample_rate: u32,
}

impl Clone for PiperEngine {
    fn clone(&self) -> Self {
        Self {
            synthesizer: Arc::clone(&self.synthesizer),
            sample_rate: self.sample_rate,
        }
    }
}

impl PiperEngine {
    pub fn new(config: &PiperBackendConfig) -> Result<Self, String> {
        let config_path = resolve_config_path(config)?;
        let model = piper_rs::from_config_path(&config_path).map_err(|err| err.to_string())?;
        let synth = PiperSpeechSynthesizer::new(model).map_err(|err| err.to_string())?;
        let info = synth
            .clone_model()
            .audio_output_info()
            .map_err(|err| err.to_string())?;
        Ok(Self {
            synthesizer: Arc::new(synth),
            sample_rate: info.sample_rate as u32,
        })
    }
}

impl TTSEngine for PiperEngine {
    fn synthesize(&self, text: &str) -> Result<Vec<AudioFrame>, String> {
        let mut pcm = Vec::new();
        let audio = self
            .synthesizer
            .synthesize_parallel(text.to_string(), None)
            .map_err(|err| err.to_string())?;
        for result in audio {
            let chunk = result.map_err(|err| err.to_string())?;
            pcm.extend(chunk.samples.to_i16_vec());
        }
        Ok(chunk_audio_samples(pcm, self.sample_rate, text.len()))
    }
}

fn resolve_config_path(config: &PiperBackendConfig) -> Result<PathBuf, String> {
    if let Some(path) = &config.config_path {
        return Ok(PathBuf::from(path));
    }
    let model_path = Path::new(&config.model_path);
    let stem = model_path
        .file_stem()
        .ok_or_else(|| "Unable to derive Piper config path".to_string())?;
    let base = stem.to_string_lossy();
    let candidates = [
        model_path.with_file_name(format!("{base}.json")),
        model_path.with_file_name(format!("{base}.onnx.json")),
    ];
    candidates
        .into_iter()
        .find(|path| path.exists())
        .ok_or_else(|| "Piper config file not found next to model".to_string())
}
