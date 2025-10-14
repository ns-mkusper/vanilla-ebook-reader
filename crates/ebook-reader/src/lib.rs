pub mod app;

pub use app::run;

#[cfg(target_os = "android")]
mod android;
