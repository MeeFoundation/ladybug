#!/bin/sh
# LadybugDB's sources with its vector extension linked in statically, into
# the directory given (default .lbug-src): the lbug crate's own engine sources
# (lbug-src, the engine its Rust bindings were written against, checked by
# cargo against crates.io's checksum), LadybugDB's extensions repository at
# the commit pins.env names, and a configuration that links `vector` and
# nothing else. Moved here from mee-pdn's scripts/lbug-vector-source.sh.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/pins.env"
out="${1:-$root/.lbug-src}"

cargo fetch -q --manifest-path "$root/harness/Cargo.toml"
crate=$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/lbug-"$LBUG_VERSION" | head -1)

mkdir -p "$out"
rsync -a --delete --exclude /extension --exclude /build "$crate/lbug-src/" "$out/"

if [ "$(git -C "$out/extension" rev-parse HEAD 2>/dev/null || true)" != "$EXTENSIONS_COMMIT" ]; then
  rm -rf "$out/extension"
  git init -q "$out/extension"
  git -C "$out/extension" remote add origin https://github.com/ladybugdb/extensions.git
  git -C "$out/extension" fetch -q --depth 1 origin "$EXTENSIONS_COMMIT"
  git -C "$out/extension" checkout -q FETCH_HEAD
fi

printf '%s\n' \
  '# Written by scripts/assemble-source.sh: the vector extension linked into the engine, no other built.' \
  'add_static_link_extension(vector)' \
  > "$out/extension/extension_config.cmake"

# The extensions' CMake writes an extension's archive into the source tree,
# where one target's build overwrites another's: into the build's own
# directory instead, beside liblbug.a, as libvector_static.a.
marker='# MeeFoundation/ladybug: the vector archive beside liblbug.a'
if ! grep -q "$marker" "$out/extension/CMakeLists.txt"; then
  printf '%s\n' \
    '' \
    "$marker" \
    'if (TARGET lbug_vector_static_extension)' \
    '    set_target_properties(lbug_vector_static_extension PROPERTIES' \
    '            ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/src"' \
    '            OUTPUT_NAME "vector_static" PREFIX "lib" SUFFIX ".a")' \
    'endif ()' \
    >> "$out/extension/CMakeLists.txt"
fi

# The C API swaps handles with std::atomic_ref, which the NDK's C++ library
# lacks; elsewhere the patch changes nothing.
python3 -I "$root/scripts/lbug_ndk_atomic_ref.py" "$out"

echo "LadybugDB $LBUG_VERSION with the vector extension linked in: $out"
