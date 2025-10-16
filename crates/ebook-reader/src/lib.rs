pub mod app;

mod persistence;
#[cfg(feature = "native-audio")]
mod tts;

pub use app::run;

#[cfg(target_os = "android")]
mod android;
