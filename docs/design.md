# LadybugDB release builds: design

> **Created by Claude, awaiting proofread.** Not reviewed by a human — do not submit or circulate as approved.

This repository builds LadybugDB, the graph database behind mee-pdn's `graph-query-engine` crate, for every platform mee-pdn and its apps run on, with its vector extension linked in. It publishes the builds as immutable GitHub Releases with build provenance. mee-pdn names a release in its Cargo configuration, and the `lbug` crate downloads that release's archive when it builds, instead of compiling LadybugDB from source, which takes about 20 minutes per target. mee-pdn's CI does not change.

The repository holds no copy of LadybugDB's source. It holds the pins (`pins.env`), the two patches, a harness crate that builds and tests the engine, and the release workflow. It is not a fork, and it stops being needed on the day LadybugDB's own releases carry what is described here (see [Retiring this repository](#retiring-this-repository)).

## Why

LadybugDB's build does not belong in the mee-pdn monorepo. The graph query engine stays in mee-pdn; the database it links is built here, because:

- **Build time.** LadybugDB compiles for about 20 minutes on a developer machine, and every CI job that tests the engine would compile it again.
- **Complexity in the monorepo.** Building it in mee-pdn took two scripts, a `just` recipe, a CI step and a source tree outside git, none of it about mee-pdn.
- **A dependency is maintained by whoever takes it.** Linking LadybugDB means owning its build for our platforms. This repository is where that ownership lives, visibly.
- **No binaries in git.** GitHub builds for each operating system and architecture and publishes the results as release assets; developers fetch a release by a pinned version.

## What upstream publishes, and what is missing

LadybugDB's release v0.22.1 (`LadybugDB/ladybug`, published 2026-10-28) is immutable and carries static libraries for Linux (x86-64 and aarch64, in `compat` and `perf` variants), macOS (x86-64 and arm64) and Windows (x86-64 and arm64). mee-pdn cannot use them as they are:

| need | upstream v0.22.1 |
|---|---|
| The vector extension (HNSW index) linked into the engine | Not linked in. On desktop the engine downloads extensions at run time; on a phone it cannot. |
| Android arm64 | No archive. The C API also does not compile against the NDK's C++ library, which lacks `std::atomic_ref`. |

The `lbug` crate, though, already knows how to use a release: given `LBUG_GITHUB_REPOSITORY` and `LBUG_VERSION`, its build script downloads `liblbug-static-<system>-<architecture>.tar.gz` from that repository's release `v<version>` and links it. This repository's releases use the same names and layout, so the crate takes them as it takes upstream's.

## What a release contains

### Targets

| Rust target | archive | used by | built on | smoke test runs on |
|---|---|---|---|---|
| `x86_64-unknown-linux-gnu` | `liblbug-static-linux-x86_64-compat.tar.gz` | developers and mee-pdn's CI | Linux x86-64 runner | the runner |
| `aarch64-unknown-linux-gnu` | `liblbug-static-linux-aarch64-compat.tar.gz` | ARM Linux hosts | Linux arm64 runner | the runner |
| `aarch64-apple-darwin` | `liblbug-static-osx-arm64.tar.gz` | developers on a Mac | macOS arm64 runner | the runner |
| `aarch64-linux-android` | `liblbug-static-android-arm64.tar.gz` | the phone apps | Linux x86-64 runner with the NDK | a phone, before the release is published (below) |

The Linux archives carry upstream's `compat` name, the variant the crate asks for by default; no `perf` variant is built. A Linux archive needs a C++ library and a C library at least as new as the runner's (Ubuntu 24.04), which mee-pdn's CI and developer machines have. iOS and Windows are left out: nothing that links the engine builds for them yet. Adding a target is a line in the workflow's matrix and one in `scripts/package.sh`.

### One archive per target

The layout is flat, as upstream's is, because the `lbug` crate takes the archive's directory both for the library and for the headers:

```
liblbug.a            the engine, its bundled libraries, and the vector extension merged in
lbug.h               the C API header
lbug.hpp             the single-file C++ header
libssl.a             Android only: OpenSSL 3, which LadybugDB needs and Android does not offer
libcrypto.a          Android only
BUILD-INFO.json      what the archive was built from and with
LICENSES/            LadybugDB, its extensions, its bundled libraries, OpenSSL
```

The vector extension's archive is merged into `liblbug.a`. The `lbug` crate links `liblbug.a` whole (`+whole-archive`), so the extension's objects, and the registration that loads it with the database, reach every binary built against the crate, an Android library included, with nothing for the consumer to add.

`BUILD-INFO.json` records the release tag, the target, the `lbug` crate version and its crates.io checksum, the extensions commit, the patches, the CMake build type, `rustc` and the C++ compiler, and for Android the NDK version, the API level and the C++ library (`c++_shared`).

**Example:** the Android archive of `v0.22.1-mee.1` records `lbug` 0.22.1, extensions commit `119912e604ebbaad64072a701698d6fcf4140051`, NDK 27.1.12297006, API 24 and `c++_shared`. An app built with another NDK major version links another C++ library and must not use it.

### Tags

A release is tagged `v<LadybugDB version>-mee.<n>`, for example `v0.22.1-mee.1`; `pins.env` names both parts, and the workflow refuses a tag that does not match. The number after `mee.` starts at 1 for each LadybugDB version and goes up when anything else changes: the extensions commit, a patch, the NDK, a target added. A tag is never reused.

### Each release also carries

- `SHA256SUMS`, the digest of every archive.
- A build provenance attestation for every archive, made in the job that built it, so `gh attestation verify <archive> --repo MeeFoundation/ladybug` proves which workflow run, commit and runner produced it.
- The release attestation GitHub makes when an immutable release is published.

## How a release is built

### Inputs, all pinned here

- **The engine's source:** the `lbug` crate from crates.io at the version `pins.env` names, whose `lbug-src` directory is the engine the crate's Rust bindings were written against. Cargo checks it against the crates.io index's checksum, which `harness/Cargo.lock` records. It is the tree mee-pdn built from source before, so moving the build here changes nothing in the engine.
- **The extensions:** `github.com/ladybugdb/extensions` at the commit LadybugDB pins, with `extension_config.cmake` set to `add_static_link_extension(vector)` and nothing else.
- **Two patches**, both applied by `scripts/assemble-source.sh`, both worth offering upstream:
  - The C API swaps a database's and a connection's handle with `std::atomic_ref`, which the NDK's C++ library lacks; where it is missing, the compiler's own `__atomic_exchange_n` does the same (`scripts/lbug_ndk_atomic_ref.py`).
  - The extensions' CMake writes each archive into the source tree, where one target's build overwrites another's; the patch writes it into the build directory as `libvector_static.a`.
- **Toolchains:** the Rust toolchain mee-pdn uses (`harness/rust-toolchain.toml`), the NDK version and API level, OpenSSL for Android (built by the `openssl-src` crate at the version `pins.env` names, as Rust's `openssl` crate builds it), and the runner images.

### Built through the `lbug` crate itself

`scripts/build.sh <target>` assembles the source, then runs a release build of the crate in `harness/`, which depends on `lbug = "=<version>"` and points the crate's source build at the assembled tree. Building through the crate, rather than calling CMake directly, keeps every CMake definition and compiler flag the one a source build of the crate uses. `scripts/package.sh <target>` then merges the extension into the engine's archive, adds the headers, licences and `BUILD-INFO.json`, and writes `dist/<archive>.tar.gz`.

For Android the build goes through `cargo ndk`, with the NDK's CMake toolchain wrapped by `android/android.toolchain.cmake`, which points LadybugDB's search for OpenSSL at the Android build of OpenSSL and away from the build machine's.

### Checked before it is published

`harness/tests/vector.rs` opens a database, creates a vector index, adds three vectors and checks the two nearest come back in order. Each job runs it where the runner can run the target's code: Linux x86-64, Linux arm64 and macOS. A job whose test fails publishes nothing.

Android cannot run on a hosted runner. The workflow therefore creates a **draft** release; drafts stay editable. Before publishing, a person builds the graph query engine's vector-index test (mee-pdn's `crates/graph-query-engine/tests/vector_index.rs`) for arm64 against the draft's Android archive and runs it on a phone over `adb`. Publishing the draft makes the release immutable: from then on its assets and its tag cannot change.

### The workflow, in order

1. A push of a tag `v*-mee.*` starts `.github/workflows/release.yml`.
2. One job per target checks the tag against `pins.env`, builds, runs the smoke test where it can, packs the archive, and attests its provenance.
3. A last job collects the archives, writes `SHA256SUMS`, and creates the draft release with all of them.
4. A person checks the Android archive on a phone and publishes the draft.

The repository's settings turn on immutable releases and protect `v*` tags.

### Building locally

`sh scripts/build.sh x86_64-unknown-linux-gnu` produces the same archive in `dist/`. It needs CMake, a C++ compiler and OpenSSL 3's development files; the Android build also needs the NDK (`ANDROID_NDK_HOME`) and `cargo-ndk`.

## How mee-pdn uses a release

### Two settings, nothing else

mee-pdn's root `.cargo/config.toml` names the release:

```toml
[env]
LBUG_GITHUB_REPOSITORY = "MeeFoundation/ladybug"
LBUG_VERSION = "0.22.1-mee.1"
```

The `lbug` crate's build script then downloads the archive for the build machine from that release, into its own build directory, and links it. Nothing runs before cargo: no script, no `just` recipe, no CI step. A clean build downloads the archive once; CI's cache of `target/` keeps it.

Because the archive arrives already built, nothing in mee-pdn depends on CMake any more. Linking still needs OpenSSL 3 on Linux and macOS, as the engine always did.

**What the download trusts.** The `lbug` crate checks no digest. An immutable release stands in for one: once published, no asset of the release can be replaced, and its tag cannot be moved. The repository must therefore stay public, so that every developer and CI can download without a token, and its releases immutable.

### Android

The `lbug` crate picks an archive by the build machine's system, so a build for Android on Linux would fetch the Linux archive. A build for Android names the Android archive itself: it downloads `liblbug-static-android-arm64.tar.gz`, checks it against the release's `SHA256SUMS`, and sets `LBUG_LIBRARY_DIR`, `LBUG_INCLUDE_DIR` and `OPENSSL_DIR` to its directory, which the crate then links in place of any download. `OPENSSL_DIR` matters as much as the other two: without it, the crate adds the build machine's library directories (`/usr/lib/x86_64-linux-gnu` among them) to the link, ahead of the NDK's, and the Android link fails on the build machine's `libc` and `libstdc++`. An application that builds the engine for Android does this in its own build. mee-pdn's own Android build (`pdn-mobile`) does not link the engine.

### What left mee-pdn

| before, in mee-pdn | now |
|---|---|
| `scripts/lbug-vector-source.sh` | `scripts/assemble-source.sh` here |
| `scripts/lbug_ndk_atomic_ref.py` | `scripts/lbug_ndk_atomic_ref.py` here |
| `just lbug-vector-source`, and its two CI steps | nothing: the `lbug` crate downloads the release |
| `LBUG_BUILD_FROM_SOURCE`, `LBUG_SOURCE_DIR` in `.cargo/config.toml` | `LBUG_GITHUB_REPOSITORY`, `LBUG_VERSION` |
| the crate's `build.rs`, linking the extension's archive | nothing: the extension is inside `liblbug.a` |
| `[profile.dev.package.lbug] opt-level = 3` | nothing: the engine arrives optimized |

## Upgrading LadybugDB

1. Here: change `pins.env` and `harness/Cargo.toml` to the new version and the extensions commit LadybugDB pins, regenerate `harness/Cargo.lock`, check that both patches still apply or are no longer needed, and push a tag `v<new version>-mee.1`.
2. Here: check the draft's Android archive on a phone, then publish it.
3. In mee-pdn: change `lbug = "=<new version>"` in the crate's `Cargo.toml` and `LBUG_VERSION` in `.cargo/config.toml`, in one pull request, so the crate's bindings and the library they link come from the same version. Other workspaces that link the engine follow.

A mismatch between the bindings and the archive shows at compile or link time, never silently: the bindings compile against the archive's own headers.

## Retiring this repository

The best outcome is that LadybugDB publishes this itself. What to ask of LadybugDB's maintainers:

- Static archives with the vector extension linked in, or the extension's static archive beside the engine's, for each platform they already publish.
- An Android arm64 archive, with the `atomic_ref` fallback merged upstream.
- The extension archive written into the build directory, with that patch merged upstream.

Once a LadybugDB release carries all of it, mee-pdn's `.cargo/config.toml` names `LadybugDB/ladybug` and its version, and this repository is archived with a note pointing there.

## Open questions

- **Who administers the repository**: turns on immutable releases, protects `v*` tags, and publishes drafts after the phone check.
- **Who contacts LadybugDB's maintainers**, and whether a shared community channel exists.
- **The repository's name.** `MeeFoundation/ladybug` carries upstream's name, which can read as a fork; the README says what it is, but a name such as `ladybug-builds` would say it before anyone opens it. Renaming changes `LBUG_GITHUB_REPOSITORY` in every workspace that names this repository.
- **Targets beyond the four above**: iOS when an iOS app links the engine, Windows, and `x86_64-linux-android` for the emulator.
- **Archive size.** The Linux engine archive is about 150 MB before compression; how much CI caching matters follows from the compressed size.
