# CI and releases

[CI](https://github.com/rayzor-blade/ashui/actions/workflows/ci.yml) runs on
pushes to `main`, pull requests and manual dispatch. It checks Haxelib archive
contents, builds and tests the native library, runs the CSS and drawing tests,
and compiles a consumer of all four framework packages through Haxelib.

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
- Enter a version tag such as `v0.1.0` to publish that version from the selected
  ref. Pushing a `v*` tag also starts a versioned release automatically.

Version tags are normalized to Haxelib versions; for example,
`v2026.10.07` becomes `2026.10.7`. Invalid versions fail before native builds
start. Publication waits for every native target and the installed-package
consumer check to pass.

The workflow publishes GitHub release assets. Submit the generated ZIPs to
Haxelib separately when the version is ready for the registry.
