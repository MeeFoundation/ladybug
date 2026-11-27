#!/bin/sh
# OpenSSL 3 for Android arm64, static, which LadybugDB needs and Android does
# not offer apps. Built by the openssl-src crate, the source and configuration
# Rust's own openssl crate builds with, into the directory given.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/pins.env"
out="${1:?the directory to install OpenSSL into}"
if [ -f "$out/lib/libssl.a" ] && [ -f "$out/lib/libcrypto.a" ]; then
  echo "OpenSSL for Android arm64: $out"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src"
# openssl-sys builds the vendored OpenSSL; openssl-src, named directly, holds
# it at the version pins.env names.
cat > "$work/Cargo.toml" <<TOML
[package]
name = "android-openssl"
version = "0.0.0"
edition = "2021"
publish = false
[dependencies]
openssl-sys = { version = "0.9", features = ["vendored"] }
openssl-src = "=$OPENSSL_SRC_VERSION"
[workspace]
TOML
echo 'use openssl_sys as _; fn main() {}' > "$work/src/main.rs"
cp "$root/harness/rust-toolchain.toml" "$work/"
(cd "$work" && cargo ndk -t arm64-v8a -P "$ANDROID_API" build --release)
built=$(find "$work/target" -path "*openssl-build/install" -type d | head -1)
mkdir -p "$out"
cp -R "$built/." "$out/"
# The license travels with the archive the library goes into.
license=$(find "$work/target" "${CARGO_HOME:-$HOME/.cargo}/registry/src" -path "*openssl-src-*/openssl/LICENSE.txt" 2>/dev/null | head -1)
[ -n "$license" ] && cp "$license" "$out/LICENSE.txt"
echo "OpenSSL for Android arm64: $out"
