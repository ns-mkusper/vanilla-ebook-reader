//! Piper ONNX wrapper placeholder.

use super::{AudioFrame, TTSEngine};

#[cfg_attr(feature = "bridge", flutter_rust_bridge::frb(opaque))]
#[derive(Default, Clone)]
pub struct PiperEngine;

impl TTSEngine for PiperEngine {
    fn load_model(&mut self, _path: &str) -> Result<(), String> {
        // TODO: integrate ONNX Runtime session creation here.
        Ok(())
    }

    fn synthesize(&self, text: &str) -> Result<Vec<AudioFrame>, String> {
        // TODO: generate per-phoneme timing map.
        Ok(vec![AudioFrame {
            samples: vec![0; 3200],
            sample_rate: 22_050,
            associated_text_idx: text.len(),
        }])
    }
}
