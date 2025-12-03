pub mod api;
pub mod audio;
#[cfg(feature = "bridge")]
mod bridge_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod engine;

pub use api::*;
pub use engine::EngineRegistryHandle;

#[cfg(feature = "bridge")]
pub use bridge_generated::*;

pub fn bootstrap_default_registry() {
    api::init_registry(engine::EngineRegistryHandle::default());
}
