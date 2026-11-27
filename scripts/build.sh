#!/bin/sh
# Build LadybugDB with its vector extension for one Rust target and pack the
# release archive for it into dist/: scripts/assemble-source.sh, a release
# build of the harness crate (the lbug crate built from that tree), its test
# where the build machine can run the target's code, then scripts/package.sh.
#
#   sh scripts/build.sh x86_64-unknown-linux-gnu
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/pins.env"
target="${1:?a Rust target, e.g. x86_64-unknown-linux-gnu}"

# The harness depends on the version pins.env names, or the release would
# carry another engine than its tag says.
grep -q "^lbug = \"=$LBUG_VERSION\"" "$root/harness/Cargo.toml" || {
  echo "harness/Cargo.toml does not pin lbug =$LBUG_VERSION (pins.env)" >&2
  exit 1
}

sh "$root/scripts/assemble-source.sh" "$root/.lbug-src"
export LBUG_BUILD_FROM_SOURCE=1 LBUG_SOURCE_DIR="$root/.lbug-src"
# Paths compiled into the engine (assertions name their source file) are
# written relative to this checkout, so an archive says nothing about the
# machine or the directory it was built in. Releases are built by the
# workflow alone; an archive built elsewhere is for trying out, never uploaded.
export CFLAGS="${CFLAGS:-} -ffile-prefix-map=$root/=" CXXFLAGS="${CXXFLAGS:-} -ffile-prefix-map=$root/="

cd "$root/harness"
host=$(rustc -vV | sed -n 's/^host: //p')
case "$target" in
  aarch64-linux-android)
    : "${ANDROID_NDK_HOME:?set it to NDK $ANDROID_NDK_VERSION}"
    export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
    openssl="$root/.openssl-android"
    sh "$root/scripts/android-openssl.sh" "$openssl"
    export OPENSSL_ROOT_DIR="$openssl" OPENSSL_DIR="$openssl" OPENSSL_STATIC=1
    export CMAKE_TOOLCHAIN_FILE_aarch64_linux_android="$root/android/android.toolchain.cmake"
    # The test is built, not run: no hosted runner runs arm64 Android code.
    cargo ndk -t arm64-v8a -P "$ANDROID_API" test --release --no-run
    ;;
  *-apple-*)
    OPENSSL_ROOT_DIR="$(brew --prefix openssl@3)"
    export OPENSSL_ROOT_DIR OPENSSL_DIR="$OPENSSL_ROOT_DIR"
    cargo test --release --target "$target" $( [ "$target" = "$host" ] || echo --no-run )
    ;;
  *)
    cargo test --release --target "$target" $( [ "$target" = "$host" ] || echo --no-run )
    ;;
esac

sh "$root/scripts/package.sh" "$target"
