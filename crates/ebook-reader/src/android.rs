#![cfg(target_os = "android")]

use jni::objects::{JClass, JObject};
use jni::JNIEnv;
use slint::android::{self, AndroidApp};
use std::sync::OnceLock;
use tracing::{error, info};

use crate::app;

static LOGGER_INIT: OnceLock<()> = OnceLock::new();

fn init_android_logging() {
    LOGGER_INIT.get_or_init(|| {
        android_logger::init_once(
            android_logger::Config::default()
                .with_max_level(log::LevelFilter::Info)
                .with_tag("VanillaEbook"),
        );
    });
}

fn run_with_app(app: AndroidApp) {
    if let Err(err) = android::init(app) {
        error!(?err, "failed to initialise Slint Android backend");
        return;
    }

    if let Err(err) = app::run() {
        error!(?err, "ebook reader terminated with error");
    }
}

#[no_mangle]
pub extern "C" fn android_main(app: AndroidApp) {
    init_android_logging();
    info!("android_main entry");
    run_with_app(app);
}

#[no_mangle]
pub extern "system" fn Java_com_example_vanillaebookreader_ReaderBridge_launch(
    env: JNIEnv,
    _class: JClass,
    activity: JObject,
) {
    init_android_logging();
    info!("ReaderBridge.launch invoked; Android Activity integration not yet wired");
    let _ = (env, activity);
}
