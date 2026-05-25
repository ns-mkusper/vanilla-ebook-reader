use std::ffi::CString;
use std::ptr;

use super::{AudioFrame, TTSEngine};

#[repr(C)]
struct CstWave {
    _type: *const std::os::raw::c_char,
    sample_rate: i32,
    num_samples: i32,
    num_channels: i32,
    samples: *mut i16,
}

#[repr(C)]
struct CstVoice {
    _private: [u8; 0],
}

extern "C" {
    fn flite_init() -> i32;
    fn register_cmu_us_kal(voxdir: *const std::os::raw::c_char) -> *mut CstVoice;
    fn unregister_cmu_us_kal(voice: *mut CstVoice);
    fn flite_text_to_wave(text: *const std::os::raw::c_char, voice: *mut CstVoice) -> *mut CstWave;
    fn delete_wave(wave: *mut CstWave);
}

pub struct FliteEngine;

impl FliteEngine {
    pub fn new() -> Self {
        Self
    }
}

impl TTSEngine for FliteEngine {
    fn synthesize(&self, text: &str) -> Result<Vec<AudioFrame>, String> {
        let text = CString::new(text)
            .map_err(|_| "Flite text contains an interior NUL byte".to_string())?;
        unsafe {
            flite_init();
            let voice = register_cmu_us_kal(ptr::null());
            if voice.is_null() {
                return Err("Failed to register embedded Flite cmu_us_kal voice".to_string());
            }
            let wave = flite_text_to_wave(text.as_ptr(), voice);
            unregister_cmu_us_kal(voice);
            if wave.is_null() {
                return Err("Embedded Flite returned no audio".to_string());
            }

            let sample_rate = (*wave).sample_rate as u32;
            let sample_count = (*wave).num_samples.max(0) as usize;
            let channels = (*wave).num_channels.max(1) as usize;
            let raw_samples = std::slice::from_raw_parts((*wave).samples, sample_count * channels);
            let samples = if channels == 1 {
                raw_samples.to_vec()
            } else {
                raw_samples
                    .chunks(channels)
                    .map(|frame| frame.iter().map(|sample| *sample as i32).sum::<i32>() / channels as i32)
                    .map(|sample| sample.clamp(i16::MIN as i32, i16::MAX as i32) as i16)
                    .collect()
            };
            delete_wave(wave);

            if samples.is_empty() || sample_rate == 0 {
                return Err("Embedded Flite produced empty audio".to_string());
            }

            Ok(vec![AudioFrame {
                samples,
                sample_rate,
                associated_text_idx: 0,
            }])
        }
    }
}
