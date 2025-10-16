pub mod app;

mod persistence;

pub use app::run;

#[cfg(target_os = "android")]
mod android;
