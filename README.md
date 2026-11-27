# LadybugDB release builds

> **Created by Claude, awaiting proofread.** Not reviewed by a human — do not submit or circulate as approved.

Prebuilt [LadybugDB](https://github.com/LadybugDB/ladybug) static libraries with the vector extension (HNSW index) linked in, for the platforms MeeFoundation's apps run on, Android among them. mee-pdn's `graph-query-engine` crate links them instead of compiling LadybugDB itself.

This is not a fork. The repository holds no LadybugDB source: only the pins, two small patches, a harness that builds and tests the engine, and the release workflow. LadybugDB is developed upstream.

## Using a release

In a Cargo workspace that depends on the `lbug` crate, name the release in `.cargo/config.toml`:

```toml
[env]
LBUG_GITHUB_REPOSITORY = "MeeFoundation/ladybug"
LBUG_VERSION = "0.22.1-mee.1"
```

The `lbug` crate's build script downloads the archive for the build machine and links it. A build for Android sets `LBUG_LIBRARY_DIR` and `LBUG_INCLUDE_DIR` to the unpacked `liblbug-static-android-arm64.tar.gz` instead, since the crate picks an archive by the build machine.

Releases are immutable and every archive carries a build provenance attestation:

```bash
gh attestation verify liblbug-static-linux-x86_64-compat.tar.gz --repo MeeFoundation/ladybug
```

## Making a release

1. Set the versions in `pins.env` (and `harness/Cargo.toml` when LadybugDB's version changes).
2. Push the tag `pins.env` names, `v<LBUG_VERSION>-mee.<MEE_RELEASE>`. The workflow builds every target and creates a draft release.
3. Check the draft's Android archive on a phone: build mee-pdn's `graph-query-engine` vector-index test for arm64 against it and run it. Then publish the draft.

To build one target locally: `sh scripts/build.sh x86_64-unknown-linux-gnu`, which leaves the archive in `dist/`.

The design, and what to ask upstream so this repository can be retired: [docs/design.md](docs/design.md).
