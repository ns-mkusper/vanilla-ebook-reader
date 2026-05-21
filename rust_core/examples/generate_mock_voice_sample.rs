use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;

use rust_core::engine::EngineRegistryHandle;

const SAMPLE_TEXT: &str =
    "Screenshot fixture: a copyright-free sample paragraph ready to read aloud.";
const SAMPLE_RATE: u32 = 16_000;
const WORD_SECONDS: f32 = 0.28;
const SILENCE_SECONDS: f32 = 0.05;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let output = env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("target/just_read_it_voice_sample.wav"));

    let registry = EngineRegistryHandle::default();
    let engine = registry.mock_engine("mock-orbit");
    let frames = engine.synthesize(SAMPLE_TEXT)?;

    let samples: Vec<i16> = frames
        .iter()
        .flat_map(|frame| frame.samples.iter().copied())
        .collect();
    validate_audio(&frames, &samples)?;

    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&output, wav_bytes(&samples, SAMPLE_RATE)?)?;
    println!(
        "Generated validated voice sample: {} ({} samples, {:.2}s)",
        output.display(),
        samples.len(),
        samples.len() as f32 / SAMPLE_RATE as f32
    );
    Ok(())
}

fn validate_audio(frames: &[rust_core::engine::AudioFrame], samples: &[i16]) -> Result<(), String> {
    if frames.is_empty() {
        return Err("voice sample produced no frames".to_string());
    }
    if frames.iter().any(|frame| frame.sample_rate != SAMPLE_RATE) {
        return Err("voice sample used an unexpected sample rate".to_string());
    }

    let word_count = SAMPLE_TEXT.split_whitespace().count();
    let expected_per_word = ((SAMPLE_RATE as f32 * WORD_SECONDS) as usize)
        + ((SAMPLE_RATE as f32 * SILENCE_SECONDS) as usize);
    let expected_samples = word_count * expected_per_word;
    if samples.len() != expected_samples {
        return Err(format!(
            "voice sample length mismatch: got {}, expected {}",
            samples.len(),
            expected_samples
        ));
    }

    let max_amplitude = samples.iter().map(|sample| sample.abs()).max().unwrap_or(0);
    if max_amplitude < 2_000 {
        return Err(format!(
            "voice sample is too quiet: max amplitude {max_amplitude}"
        ));
    }

    for word_index in 0..word_count {
        let start = word_index * expected_per_word;
        let voiced_end = start + (SAMPLE_RATE as f32 * WORD_SECONDS) as usize;
        let voiced = &samples[start..voiced_end];
        let voiced_peak = voiced.iter().map(|sample| sample.abs()).max().unwrap_or(0);
        if voiced_peak < 1_000 {
            return Err(format!("word {word_index} has no audible voiced segment"));
        }
    }

    Ok(())
}

fn wav_bytes(samples: &[i16], sample_rate: u32) -> io::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    let data_len = samples.len() as u32 * 2;
    let byte_rate = sample_rate * 2;

    bytes.write_all(b"RIFF")?;
    bytes.write_all(&(36 + data_len).to_le_bytes())?;
    bytes.write_all(b"WAVE")?;
    bytes.write_all(b"fmt ")?;
    bytes.write_all(&16u32.to_le_bytes())?;
    bytes.write_all(&1u16.to_le_bytes())?;
    bytes.write_all(&1u16.to_le_bytes())?;
    bytes.write_all(&sample_rate.to_le_bytes())?;
    bytes.write_all(&byte_rate.to_le_bytes())?;
    bytes.write_all(&2u16.to_le_bytes())?;
    bytes.write_all(&16u16.to_le_bytes())?;
    bytes.write_all(b"data")?;
    bytes.write_all(&data_len.to_le_bytes())?;
    for sample in samples {
        bytes.write_all(&sample.to_le_bytes())?;
    }
    Ok(bytes)
}
