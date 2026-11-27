#!/bin/sh
# Pack what scripts/build.sh built for one Rust target into
# dist/<archive>.tar.gz, flat, as LadybugDB's own static archives are laid
# out, so the lbug crate's downloader takes it as it takes theirs:
#
#   liblbug.a         the engine with the vector extension merged in; the lbug
#                     crate links it whole, so the extension is linked too
#   lbug.h, lbug.hpp  the C API and the single-file C++ header
#   libssl.a, libcrypto.a, on Android: OpenSSL 3, which the platform lacks
#   BUILD-INFO.json   what the archive was built from and with
#   LICENSES/         LadybugDB's, its extensions', its bundled libraries', OpenSSL's
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/pins.env"
target="${1:?a Rust target}"
tag="v$LBUG_VERSION-mee.$MEE_RELEASE"

# The names LadybugDB's releases use, which the lbug crate's downloader asks
# for by the build machine's system and architecture. Android has no
# upstream name; an Android build names the directory itself.
case "$target" in
  x86_64-unknown-linux-gnu)  name=liblbug-static-linux-x86_64-compat ;;
  aarch64-unknown-linux-gnu) name=liblbug-static-linux-aarch64-compat ;;
  aarch64-apple-darwin)      name=liblbug-static-osx-arm64 ;;
  x86_64-apple-darwin)       name=liblbug-static-osx-x86_64 ;;
  aarch64-linux-android)     name=liblbug-static-android-arm64 ;;
  *) echo "no archive name for $target" >&2; exit 1 ;;
esac

case "$target" in
  aarch64-linux-android) dir=target/aarch64-linux-android ;;
  *) dir=target/$target ;;
esac
built=$(ls -td "$root/harness/$dir"/release/build/lbug-*/out/build/src 2>/dev/null | while read -r d; do
  [ -f "$d/liblbug.a" ] && [ -f "$d/libvector_static.a" ] && { echo "$d"; break; }
done)
[ -n "$built" ] || { echo "no liblbug.a with libvector_static.a beside it under harness/$dir" >&2; exit 1; }

stage="$root/dist/$name"
rm -rf "$stage"
mkdir -p "$stage/LICENSES"

case "$target" in
  *-apple-*) libtool -static -o "$stage/liblbug.a" "$built/liblbug.a" "$built/libvector_static.a" ;;
  *)
    ar=ar
    if [ "$target" = aarch64-linux-android ]; then
      ar=$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-ar | head -1)
    fi
    printf 'create %s\naddlib %s\naddlib %s\nsave\nend\n' \
      "$stage/liblbug.a" "$built/liblbug.a" "$built/libvector_static.a" | "$ar" -M
    ;;
esac
cp "$built/lbug.hpp" "$stage/"
cp "$root/.lbug-src/src/include/c_api/lbug.h" "$stage/"

if [ "$target" = aarch64-linux-android ]; then
  cp "$root/.openssl-android/lib/libssl.a" "$root/.openssl-android/lib/libcrypto.a" "$stage/"
  [ -f "$root/.openssl-android/LICENSE.txt" ] && cp "$root/.openssl-android/LICENSE.txt" "$stage/LICENSES/OpenSSL"
  # The NDK's CMake toolchain compiles with -g whatever the build type; like
  # the other targets' archives, this one carries no debug information.
  strip=$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-strip | head -1)
  "$strip" --strip-debug "$stage/liblbug.a" "$stage/libssl.a" "$stage/libcrypto.a"
fi

curl -fsSL "https://raw.githubusercontent.com/LadybugDB/ladybug/v$LBUG_VERSION/LICENSE" -o "$stage/LICENSES/LadybugDB"
cp "$root/.lbug-src/extension/LICENSE" "$stage/LICENSES/ladybugdb-extensions"
for license in "$root"/.lbug-src/third_party/*/LICENSE*; do
  lib=$(basename "$(dirname "$license")")
  cp "$license" "$stage/LICENSES/third_party-$lib"
done

checksum=$(awk '/^name = "lbug"$/ {found=1} found && /^checksum/ {gsub(/"/, "", $3); print $3; exit}' "$root/harness/Cargo.lock")
case "$target" in
  aarch64-linux-android) cxx="$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/clang++ | head -1) --version" ;;
  *) cxx="c++ --version" ;;
esac
android=null
if [ "$target" = aarch64-linux-android ]; then
  android="{\"ndk\": \"$ANDROID_NDK_VERSION\", \"api\": $ANDROID_API, \"stl\": \"c++_shared\", \"openssl_src\": \"$OPENSSL_SRC_VERSION\"}"
fi
cat > "$stage/BUILD-INFO.json" <<JSON
{
  "tag": "$tag",
  "target": "$target",
  "lbug_crate": {"version": "$LBUG_VERSION", "crates_io_checksum": "$checksum"},
  "extensions_commit": "$EXTENSIONS_COMMIT",
  "static_extensions": ["vector"],
  "patches": ["atomic-ref-fallback (scripts/lbug_ndk_atomic_ref.py)", "extension-archive-dir (scripts/assemble-source.sh)"],
  "cmake_build_type": "Release",
  "rustc": "$(rustc -V)",
  "cxx": "$($cxx | head -1)",
  "android": $android,
  "source_commit": "$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)"
}
JSON

tar -czf "$root/dist/$name.tar.gz" -C "$stage" .
( cd "$root/dist" && sha256sum "$name.tar.gz" 2>/dev/null || shasum -a 256 "$name.tar.gz" )
