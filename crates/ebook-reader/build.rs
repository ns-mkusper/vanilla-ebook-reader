use std::env;

fn main() {
    link_native_audio();
    slint_build::compile("ui/app.slint").expect("failed to compile Slint UI");
}

#[allow(unused)]
fn link_native_audio() {
    let native_audio_enabled = env::var_os("CARGO_FEATURE_NATIVE_AUDIO").is_some();

    if !native_audio_enabled {
        return;
    }

    if let Some(lib_dir) = env::var_os("FLITE_LIB_DIR") {
        println!("cargo:rustc-link-search=native={}", lib_dir.to_string_lossy());
        let link_kind = env::var("FLITE_LINK_KIND").unwrap_or_else(|_| "dylib".into());
        let lib_name = env::var("FLITE_LINK_LIB").unwrap_or_else(|_| "flite".into());
        match link_kind.as_str() {
            "static" => println!("cargo:rustc-link-lib=static={}", lib_name),
            _ => println!("cargo:rustc-link-lib={}", lib_name),
        }
        if let Some(include_dir) = env::var_os("FLITE_INCLUDE_DIR") {
            println!(
                "cargo:include={}",
                include_dir.to_string_lossy()
            );
        }
        return;
    }

    #[cfg(all(target_env = "msvc"))]
    {
        vcpkg::Config::new()
            .emit_includes(true)
            .find_package("flite")
            .expect("vcpkg to provide the flite package");
    }
}
