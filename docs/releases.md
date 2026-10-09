# CI and releases

[CI](https://github.com/rayzor-blade/ashui/actions/workflows/ci.yml) runs on
pushes to `main`, pull requests and manual dispatch. It checks Haxelib archive
contents, builds and tests the native library, runs the CSS and drawing tests,
and compiles a consumer of all four framework packages through Haxelib.

## Native dependency

The native implementation lives in
[project-blinc/blinc_abi](https://github.com/project-blinc/blinc_abi).
Ashui pins its Git revision in `Cargo.toml` and `Cargo.lock`. The local
`ashui-native` target only re-exports that crate to preserve the library name
`blinc_abi.hdll` used by the Haxe bindings and release archives.

Demo, test and snapshot runners build this same target. Snapshot watch mode
resolves the dependency's source directory through Cargo metadata, so it also
follows a contributor's local Cargo patch. Updating the pinned revision requires
the Haxe integration tests and offscreen snapshot checks before a new milestone
commit.

## Nightly

The [release workflow](https://github.com/rayzor-blade/ashui/actions/workflows/release.yml)
runs daily at **03:47 UTC**. It skips a commit that already has a successful
nightly publication. New builds update the rolling
[`nightly` prerelease](https://github.com/rayzor-blade/ashui/releases/tag/nightly).

Every release builds Linux x86_64/aarch64, macOS x86_64/aarch64 and Windows
x86_64 native libraries. The packaging job installs and compiles the generated
Haxelibs and verifies that the core's build macro stages the host HDLL before
publication.

Assets include `ashui.zip`, `ashui-components.zip`, `ashui-canvaskit.zip`,
`ashui-media.zip`, and the five platform HDLLs. The core ZIP bundles every
desktop HDLL; all four packages use matching internal dependency versions.
Nightlies retain the version from `haxelib.json` and are marked as prereleases.

## Manual validation or release

Open the release workflow and choose **Run workflow**:

- Leave `release_tag` empty to build and validate, with downloadable workflow
  artifacts.
- Enter `nightly` to publish a nightly immediately.
- Enter a version tag such as `v0.1.1` to publish that version from the selected
  ref. Pushing a `v*` tag also starts a versioned release automatically.

Version tags are normalized to Haxelib versions; for example,
`v2026.10.07` becomes `2026.10.7`. Invalid versions fail before native builds
start. Publication waits for every native target and the installed-package
consumer check to pass.

## Haxelib publication

Each repository has a separate **publish Haxelib** workflow. Versioned release
builds call it after their GitHub assets are published. It can also submit an
existing release manually: enter its `release_tag` and enable `publish`.
Leave `publish` unchecked to validate the ZIPs without submitting. Nightly
releases can be validated, but are never submitted to the registry.

The publishing account is **rayzor**. Configure `HAXELIB_PASSWORD` as a GitHub
Actions secret in `ash`, `hlwgpu`, `hlwindow`, `hlavi` and `ashui`. The workflow
uses the existing account; it does not register one.

For the first publication, use ashui's
[publish Haxelib stack](https://github.com/rayzor-blade/ashui/actions/workflows/publish-stack.yml)
workflow. Select an existing versioned release from each repository. It runs
in this order:

1. Ash publishes `ash-future`, then `ash-simd`. These have their own package
   versions, independent of the Ash runtime tag.
2. `hlwgpu`, `hlwindow` and `hlavi` publish their bindings and native libraries.
3. ashui publishes `ashui`, `ashui-components`, `ashui-canvaskit`, then
   `ashui-media`, with matching internal dependency versions.

The stack workflow only needs the secret in ashui; individual repository
publication uses that repository's secret. Missing registry dependencies
block a batch before its first submission. Already published versions are
skipped, and submission refuses to overwrite a version.

The stack also installs all nine release ZIPs in a fresh Haxelib repository,
compiles an HXX consumer and verifies all six native install macros, including
the stock HashLink Future and SIMD libraries, before any registry submission. Validation can run before the
packages are registered on Haxelib.

The publisher validates native contents or checksummed downloads before
submission. Publish copies of existing release ZIPs set `rayzor` as the first contributor
and keep `darmie` as an additional contributor. This also supplies the missing
contributor in older `ash-future` releases, preserving the Haxe sources and
native binaries.

### Installing before registry publication

Haxelib installs the dependencies in `haxelib.json` before compilation. A
compile macro cannot replace that step. Once packages are registered,
`haxelib install ashui-media` installs the complete media dependency chain.
`ash-simd` is separately installable; ashui currently does not depend on it.

Before publication, install the GitHub release ZIPs in the same order using
`haxelib install <release-zip-url> --always --skip-dependencies`. Also install
the existing `hashlink` and `tink_hxx` packages. This avoids native builds:
the installed `extraParams.hxml` macros stage the bundled host HDLLs, and
hlavi's macro downloads and caches its checksummed host binary.
