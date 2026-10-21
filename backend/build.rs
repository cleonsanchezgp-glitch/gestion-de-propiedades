use std::{env, fs, path::PathBuf, time::{SystemTime, UNIX_EPOCH}};

fn main() {
    for name in ["AELIUM_RELEASE_ID", "AELIUM_BUILD_ID", "AELIUM_API_CONTRACT"] {
        println!("cargo:rerun-if-env-changed={name}");
    }
    println!("cargo:rerun-if-changed=migrations");
    println!("cargo:rerun-if-changed=src");
    println!("cargo:rerun-if-changed=Cargo.toml");
    println!("cargo:rerun-if-changed=Cargo.lock");
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR"));
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH).expect("clock").as_nanos();
    let release = env::var("AELIUM_RELEASE_ID").unwrap_or_else(|_| format!("dev-{stamp}"));
    let build = env::var("AELIUM_BUILD_ID").unwrap_or_else(|_| format!("dev-build-{stamp}"));
    let contract = env::var("AELIUM_API_CONTRACT").unwrap_or_else(|_| "propiedades-v3".into());
    for value in [&release, &build, &contract] {
        assert!(!value.is_empty() && value.len() <= 80 && value.as_bytes()[0].is_ascii_alphanumeric() && value.bytes().all(|c| c.is_ascii_alphanumeric() || b"._-".contains(&c)), "Invalid build identifier");
    }
    if env::var("PROFILE").as_deref() == Ok("release") {
        assert!(env::var("AELIUM_RELEASE_ID").is_ok() && env::var("AELIUM_BUILD_ID").is_ok(), "Release builds require explicit AELIUM_RELEASE_ID and AELIUM_BUILD_ID");
    }
    fs::write(out.join("release_metadata.rs"), format!("pub const RELEASE_ID: &str = {release:?};\npub const BUILD_ID: &str = {build:?};\npub const API_CONTRACT: &str = {contract:?};\n")).expect("write metadata");
}
