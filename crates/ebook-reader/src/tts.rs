#![cfg(feature = "native-audio")]

use std::collections::HashMap;
use std::ffi::CString;
use std::sync::{Arc, Once, RwLock};

use anyhow::{anyhow, Context, Result};
use once_cell::sync::Lazy;

/// Represents a block of PCM audio data returned by a speech engine.
pub struct AudioChunk {
    pub samples: Vec<i16>,
    pub sample_rate: u32,
    pub channels: u16,
}

/// Options passed to a speech engine when synthesizing speech.
pub struct SynthesisOptions<'a> {
    pub rate: f32,
    pub voice: Option<&'a str>,
}

/// Trait describing a pluggable text-to-speech backend.
pub trait SpeechEngine: Send + Sync {
    /// Stable identifier for the engine (e.g., `"flite"`).
    fn id(&self) -> &'static str;
    /// Human readable description.
    fn description(&self) -> &'static str;
    /// Engine-level default voice identifier.
    fn default_voice(&self) -> &'static str;
    /// Optional list of voices known to the engine.
    fn supported_voices(&self) -> &[&'static str] {
        &[self.default_voice()]
    }
    /// Perform synthesis for a block of text.
    fn synthesize(&self, text: &str, opts: &SynthesisOptions<'_>) -> Result<AudioChunk>;
}

struct TtsState {
    engines: HashMap<String, Arc<dyn SpeechEngine>>,
    default_engine: String,
}

static REGISTRY: Lazy<RwLock<TtsState>> = Lazy::new(|| {
    let mut engines: HashMap<String, Arc<dyn SpeechEngine>> = HashMap::new();

    #[cfg(feature = "tts-flite")]
    {
        if let Ok(engine) = FliteEngine::new() {
            let id = engine.id().to_string();
            engines.insert(id, Arc::new(engine));
        }
    }

    if engines.is_empty() {
        let null = Arc::new(NullEngine);
        engines.insert(null.id().to_string(), null);
    }

    let default_engine = engines.keys().next().cloned().unwrap_or_else(|| "null".to_string());
    RwLock::new(TtsState {
        engines,
        default_engine,
    })
});

/// Handle returned when resolving a speech engine and voice selection.
#[derive(Clone)]
pub struct EngineHandle {
    pub engine_id: String,
    pub engine: Arc<dyn SpeechEngine>,
    pub voice: Option<String>,
}

impl EngineHandle {
    #[must_use]
    pub fn voice(&self) -> Option<&str> {
        self.voice.as_deref()
    }
}

/// Register an additional speech engine at runtime.
pub fn register_engine(engine: Arc<dyn SpeechEngine>) {
    let mut state = REGISTRY
        .write()
        .expect("TTS registry poisoned during registration");
    let id = engine.id().to_string();
    state.engines.insert(id.clone(), engine);
    if state.default_engine == "null" {
        state.default_engine = id;
    }
}

/// Replace the default engine used when no explicit engine id is provided.
pub fn set_default_engine(id: &str) -> Result<()> {
    let mut state = REGISTRY
        .write()
        .expect("TTS registry poisoned while setting default engine");
    if state.engines.contains_key(id) {
        state.default_engine = id.to_string();
        Ok(())
    } else {
        Err(anyhow!("unknown TTS engine '{id}'"))
    }
}

pub fn available_engines() -> Vec<String> {
    let state = REGISTRY
        .read()
        .expect("TTS registry poisoned while listing engines");
    state.engines.keys().cloned().collect()
}

pub fn resolve_engine(engine_id: Option<&str>, voice: Option<String>) -> Result<EngineHandle> {
    let state = REGISTRY
        .read()
        .expect("TTS registry poisoned while resolving engine");

    let (id, engine) = if let Some(requested) = engine_id {
        match state.engines.get(requested) {
            Some(engine) => (requested.to_string(), Arc::clone(engine)),
            None => {
                return Err(anyhow!(
                    "requested TTS engine '{}' is not registered",
                    requested
                ))
            }
        }
    } else {
        let default_id = state.default_engine.clone();
        let engine = state
            .engines
            .get(&default_id)
            .cloned()
            .expect("default TTS engine missing");
        (default_id, engine)
    };

    Ok(EngineHandle {
        engine_id: id,
        engine,
        voice,
    })
}

pub fn resolve_from_environment() -> EngineHandle {
    let engine_id = std::env::var("VANILLA_TTS_ENGINE").ok();
    let voice = std::env::var("VANILLA_TTS_VOICE").ok();

    match resolve_engine(engine_id.as_deref(), voice) {
        Ok(handle) => handle,
        Err(err) => {
            tracing::warn!(?err, requested = engine_id, "unable to load requested TTS engine; falling back to default");
            resolve_engine(None, std::env::var("VANILLA_TTS_FALLBACK_VOICE").ok())
                .expect("default TTS engine must be available")
        }
    }
}

struct NullEngine;

impl SpeechEngine for NullEngine {
    fn id(&self) -> &'static str {
        "null"
    }

    fn description(&self) -> &'static str {
        "No-op speech engine"
    }

    fn default_voice(&self) -> &'static str {
        "none"
    }

    fn synthesize(&self, _text: &str, _opts: &SynthesisOptions<'_>) -> Result<AudioChunk> {
        Err(anyhow!(
            "no speech engine is configured; enable the 'native-audio' feature with a supported backend"
        ))
    }
}

#[cfg(feature = "tts-flite")]
struct FliteEngine {
    voices: Vec<&'static str>,
    default_voice: &'static str,
}

#[cfg(feature = "tts-flite")]
impl FliteEngine {
    fn new() -> Result<Self> {
        static FLITE_INIT: Once = Once::new();
        FLITE_INIT.call_once(|| unsafe {
            flite_sys::flite_init();
        });

        let mut available = Vec::new();
        for &voice in &["cmu_us_kal", "kal16", "slt", "awb", "rms"] {
            if Self::voice_exists(voice) {
                available.push(voice);
            }
        }

        if available.is_empty() {
            return Err(anyhow!(
                "flite is compiled but no voices were registered; ensure cmu_us_kal is built in"
            ));
        }

        Ok(Self {
            default_voice: available[0],
            voices: available,
        })
    }

    fn voice_exists(name: &str) -> bool {
        unsafe {
            let c_name = CString::new(name).expect("valid voice name");
            !flite_sys::flite_voice_select(c_name.as_ptr()).is_null()
        }
    }
}

#[cfg(feature = "tts-flite")]
impl SpeechEngine for FliteEngine {
    fn id(&self) -> &'static str {
        "flite"
    }

    fn description(&self) -> &'static str {
        "CLUSTERGEN voices via CMU Flite"
    }

    fn default_voice(&self) -> &'static str {
        self.default_voice
    }

    fn supported_voices(&self) -> &[&'static str] {
        &self.voices
    }

    fn synthesize(&self, text: &str, opts: &SynthesisOptions<'_>) -> Result<AudioChunk> {
        let voice_name = opts
            .voice
            .filter(|candidate| self.supported_voices().contains(candidate))
            .unwrap_or_else(|| {
                if let Some(requested) = opts.voice {
                    tracing::warn!(
                        voice = %requested,
                        "requested flite voice not available; falling back to {}",
                        self.default_voice
                    );
                }
                self.default_voice()
            });

        let c_voice =
            CString::new(voice_name).context("failed to convert voice name for flite")?;
        let c_text = CString::new(text).context("failed to convert text for flite")?;

        let wave_ptr = unsafe {
            let voice = flite_sys::flite_voice_select(c_voice.as_ptr());
            if voice.is_null() {
                return Err(anyhow!("flite could not locate voice '{voice_name}'"));
            }

            if let Some(stretch) = duration_stretch_from_rate(opts.rate) {
                let features = (*voice).features;
                if !features.is_null() {
                    let key = CString::new("duration_stretch").unwrap();
                    flite_sys::flite_feat_set_float(features, key.as_ptr(), stretch);
                }
            }

            flite_sys::flite_text_to_wave(c_text.as_ptr(), voice)
        };

        if wave_ptr.is_null() {
            return Err(anyhow!("flite returned a null waveform for synthesis"));
        }

        let chunk = unsafe {
            let wave = &*wave_ptr;

            if wave.samples.is_null() {
                flite_sys::delete_wave(wave_ptr);
                return Err(anyhow!("flite returned an empty waveform"));
            }

            let sample_count: usize = wave
                .num_samples
                .try_into()
                .context("waveform sample count overflow")?;
            let samples = std::slice::from_raw_parts(wave.samples, sample_count);
            let mut owned = Vec::with_capacity(sample_count);
            owned.extend_from_slice(samples);

            let sample_rate = if wave.sample_rate <= 0 {
                16_000
            } else {
                wave.sample_rate as u32
            };
            let channels = if wave.num_channels <= 0 {
                1
            } else {
                wave.num_channels as u16
            };

            let chunk = AudioChunk {
                samples: owned,
                sample_rate,
                channels,
            };
            flite_sys::delete_wave(wave_ptr);
            chunk
        };

        Ok(chunk)
    }
}

#[cfg(feature = "tts-flite")]
fn duration_stretch_from_rate(rate: f32) -> Option<f32> {
    if !rate.is_normal() {
        return None;
    }
    let clamped = rate.clamp(0.25, 4.0);
    Some((1.0 / clamped).clamp(0.25, 4.0))
}
