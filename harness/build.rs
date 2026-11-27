//! A source build of the lbug crate leaves the vector extension's archive
//! beside the engine's (scripts/assemble-source.sh), on the link path the
//! lbug crate names, but links only the engine. Linked whole here, so the
//! smoke test runs with the extension as a release's merged archive carries it.
fn main() {
    println!("cargo:rustc-link-lib=static:+whole-archive,-bundle=vector_static");
}
