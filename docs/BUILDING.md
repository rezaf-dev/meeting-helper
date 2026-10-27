# Building and distributing MeetingHelper

## Toolchain

Use an Apple Silicon Mac with macOS 26+, Swift 6.2+, and a macOS 26+ SDK. Install Xcode 26+ or compatible Command Line Tools. Check the active tools:

```sh
xcode-select -p
swift --version
xcrun --show-sdk-version
```

If the tools are too old, install a compatible Xcode and select its developer directory in Xcode Settings → Locations. The package has no external dependencies. Swift language mode is 5; the manifest requires Swift tools 6.2.

## Local builds

```sh
./scripts/build-app.sh          # release
./scripts/build-app.sh debug    # debug
open dist/MeetingHelper.app
open dist/MeetingHelper.app --args --demo
```

The scripts work from any working directory. Build products and module caches stay in `.build/`; app bundles and archives go to `dist/`. SwiftPM sandboxing is disabled in these helper scripts for compatibility with restricted development environments. Build only source you trust.

The bundle uses `Resources/Info.plist` for version, bundle ID, minimum macOS version, and permission messages. The build includes the MIT license in the app resources, copies committed icon assets and verifies an ad-hoc code signature. It does not regenerate or modify source assets.

To intentionally update the generated logo assets:

```sh
swift scripts/GenerateLogo.swift
iconutil -c icns .build/MeetingHelper.iconset -o Resources/AppIcon.icns
```

Review and commit the updated images together. The SVG is an editable reference; the generator contains its own drawing geometry.

## Verification

```sh
./scripts/test.sh
./scripts/chat-history-smoke-test.sh
./scripts/package-app.sh
```

Core tests use Swift Testing and mock network responses; they do not make paid AI calls or capture audio. The history probe uses a temporary archive with synthetic data. The test script explicitly loads the Swift Testing macro plugin when available to accommodate the Command Line Tools toolchain.

For a clean rebuild, quit the app, remove the generated `.build/` and `dist/` directories, then repeat the commands above. Do not remove the app's Application Support directory or preferences to clean build products: they contain user data.

Optional speech diagnostic:

```sh
mkdir -p .build
say -v Samantha -o .build/meeting-fixture.aiff 'Could you give us an estimate for the integration? I need to check the authentication changes first. Let us follow up tomorrow.'
./scripts/speech-smoke-test.sh "$PWD/.build/meeting-fixture.aiff"
```

This requires Apple's local speech service and assets. It uses synthetic audio without microphone capture or AI requests. Permission prompts, live audio devices, floating windows, and screen-sharing behavior require interactive checks. See [VALIDATION.md](VALIDATION.md).

## CI

`.github/workflows/ci.yml` runs on pushes to `main`, version tags, pull requests, and manual dispatch. It uses GitHub's `macos-26` Apple Silicon runner, executes tests and the history probe, builds a release app, and uploads its ZIP, installation DMG, and checksums as an Actions artifact. It does not request recording permissions or run speech recognition. A version-tag push also publishes a GitHub Release after the build succeeds. Branch pushes, pull requests, and manual runs only build and upload Actions artifacts.

## Release archives

```sh
./scripts/package-app.sh
```

The outputs are `dist/MeetingHelper-<version>-macOS-<architecture>.zip` and `.dmg`, each with a matching `.sha256` file. The compressed, read-only DMG contains the app and an Applications shortcut for drag-and-drop installation. The script always builds release mode first and preserves bundle metadata with `ditto`, and verifies the DMG with `hdiutil`. Verify a downloaded archive from its directory:

```sh
shasum -a 256 -c MeetingHelper-0.8.0-macOS-arm64.zip.sha256
shasum -a 256 -c MeetingHelper-0.8.0-macOS-arm64.dmg.sha256
```

For each release:

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist`.
2. Run the verification commands and relevant interactive checks. Document limitations in the release notes.
3. Commit the source, tag that commit with the matching version (for example `v0.8.0`), and let CI validate it.
4. Push the version tag. CI publishes the DMG, ZIP, checksums, and release notes automatically after all checks pass.

### Automatic GitHub releases

Once the workflow and source changes are committed and pushed to `main`, publish version 0.8.0 with:

```sh
git tag -a v0.8.0 -m "MeetingHelper v0.8.0"
git push origin v0.8.0
```

Use a new `vMAJOR.MINOR.PATCH` tag for each release, matching `CFBundleShortVersionString` in `Resources/Info.plist`. The workflow rejects mismatched or prerelease tags before building. For subsequent releases, update the version and build number, commit and push those changes, then tag that commit.

The build job runs tests, packages the app, and uploads its artifacts with read-only repository permissions. A separate job downloads those artifacts, verifies both checksums, and publishes the release using GitHub's built-in `GITHUB_TOKEN` with `contents: write`. No personal access token or signing secrets are needed. Repository or organization policies must allow Actions and that permission.

Release notes include installation instructions, the notarization limitation, CoreFixLab attribution, and GitHub's generated change summary. A release is only attempted after successful checks; pushes to `main`, pull requests, and manual workflow dispatches do not publish. Existing releases are not overwritten. If publication fails, inspect the Actions logs and any partial draft before retrying; never move a published version tag to different source.

The app in both packages is **ad-hoc signed, not notarized**. Creating a DMG does not bypass Gatekeeper. The current process does not produce a universal Intel/Apple Silicon build. Do not describe these archives as notarized releases or tell users to disable Gatekeeper globally.

For a normal downloadable macOS distribution, a maintainer needs Apple Developer Program access, Developer ID signing, hardened runtime configuration appropriate for audio capture, notarization, and ticket stapling before packaging. Those steps require separate setup and are not automated here. Never commit certificates, private keys, signing passwords, or notarization credentials.

## Repository publication

The MIT license covers source and bundled logo assets. Keep local recordings, exports, credentials, and signing material out of commits. `.gitignore` excludes common local artifacts but cannot remove an already tracked secret. Review `git diff --cached` before the first commit.

Enable GitHub private vulnerability reporting and branch protection requiring the CI job once the repository is published. No repository settings are changed by these scripts.


### GitHub description and topics

After publication, set the repository's **About** description to:

> Open-source AI meeting assistant for Mac: real-time on-device transcription, floating live captions, and English speaking help. SwiftUI + OpenRouter.

Suggested topics:

```text
macos swift swiftui apple-silicon meeting-assistant live-transcription
live-captions speech-to-text speech-recognition on-device-ai
english-learning openrouter
```

These describe the app's actual platform, features, and implementation. GitHub's default repository search checks names, descriptions, and topics; searching README text requires `in:readme`. See [GitHub repository search](https://docs.github.com/en/search-github/searching-on-github/searching-for-repositories) and [repository topics](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics).

Keep the repository public and publish the installation DMG with accurate release notes when ready. A short demo using synthetic content can help visitors understand the app. If you add a project page on corefixlab.com, describe its actual use cases and link to this repository. README wording and metadata improve clarity and discovery signals; they do not guarantee search indexing or ranking.
