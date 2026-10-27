<p align="center"><img src="Resources/Logo-preview.png" width="112" alt="MeetingHelper logo"></p>

# MeetingHelper — Live Transcription & AI Meeting Assistant for Mac

MeetingHelper is an open-source macOS app for real-time meeting transcription, floating live captions, and optional AI assistance during English conversations. Built for Apple Silicon Macs running macOS 26 or later, it transcribes microphone and system audio on-device with Apple's Speech framework.

Follow a conversation, understand unfamiliar English phrases, prepare a reply, or recap what was said. Audio stays on your Mac; optional AI help sends text through OpenRouter only when you enable sharing. Local speech-to-text works offline after Apple's speech assets are installed.

## Features

- **Real-time speech-to-text:** live English captions from your microphone, system audio, or both.
- **Floating live captions:** keep meeting subtitles visible above other windows, with adjustable text size.
- **AI meeting assistance:** explanations, reply suggestions, conversation recaps, and English speaking hints.
- A live “What I want to say” note and optional saved profile.
- **Local meeting transcripts:** saved chat history with search, copy, text export, and deletion.
- Configurable OpenRouter models and English help preferences.

## Who is it for?

- People who want live meeting captions on their Mac while working in another app.
- Non-native English speakers who want help understanding phrases and expressing a reply during calls.
- Developers looking for an open-source SwiftUI app using Apple's on-device speech recognition and OpenRouter.

## Requirements

- An Apple Silicon Mac running **macOS 26 or later**.
- **Swift 6.2 or later** and a **macOS 26+ SDK**, supplied by Xcode 26+ or compatible Apple Command Line Tools.
- Internet access for the initial download of Apple's English speech assets. Local captions work offline after installation.
- Optional: an OpenRouter API key and account credit for AI assistance.

There are no third-party Swift package dependencies. No API key is required to build the app or use local captions.

## Build and run

```sh
git clone https://github.com/rezaf-dev/meeting-helper.git
cd meeting-helper
./scripts/build-app.sh
open dist/MeetingHelper.app
```

The build defaults to release mode. Use `./scripts/build-app.sh debug` for a debug bundle. To explore without recording:

```sh
open dist/MeetingHelper.app --args --demo
```

Launch the `.app` bundle so macOS attributes capture permissions to MeetingHelper. You can open `Package.swift` in Xcode to edit the code.

These builds are ad-hoc signed for local use. They are **not Developer ID signed or notarized**; downloaded archives may be blocked by Gatekeeper. See [build and distribution notes](docs/BUILDING.md) for packaging and release requirements.

## Install from a DMG

When a release DMG is available, open it, drag **MeetingHelper** to **Applications**, then eject the disk image and launch the app from Applications. Current packages are ad-hoc signed and not notarized; Gatekeeper may block downloaded builds.

## First meeting

1. Select **Microphone**, **Meeting audio**, or both, then choose **Start captions**. Grant the requested macOS recording permissions. The first start may download speech assets.
2. Use headphones when capturing both sources. Meeting audio captures all system playback, including sounds from other apps.
3. Open **Float captions** to follow the meeting while working in another app.
4. For AI assistance, save your OpenRouter key in Settings and enable **Send meeting text through OpenRouter**. Select a model available to your account; provider availability and pricing can change.
5. Write keywords in **What I want to say**, then choose **Help me reply**, **Explain that**, or **Catch me up**.

See the [user guide](docs/USER_GUIDE.md) for permissions, shortcuts, profiles, history, and automatic help.

## Privacy and limitations

- AI sharing is off by default. The app does not upload or save audio recordings.
- Enabled AI requests send meeting text, notes, drafts, and any included profile through OpenRouter to the selected provider. Their data policies apply. Loading the model browser also contacts OpenRouter's public catalog.
- **API keys are stored unencrypted in local app preferences.** Remove them in Settings when no longer needed.
- **Chat history is unencrypted JSON** in `~/Library/Application Support/MeetingHelper/Chats/`. It includes captions, AI answers, and request context. Delete saved chats through History; manage exported copies separately.
- Source labels distinguish microphone from system audio; they do not identify individual speakers. Recognition and AI answers can be wrong.
- A visible floating panel can appear in screen shares. The capture-exclusion setting is best effort. Share a specific app window or use an unshared display, and check the recipient's view.

Live device capture, real AI completions, and sustained meeting performance require manual validation. See [validation notes](docs/VALIDATION.md). Obtain any consent required to transcribe or share meeting content.

## Frequently asked questions

### Does meeting transcription work offline?

Yes. Captions use Apple's on-device speech recognition and work offline once the English speech assets are installed. AI explanations, reply suggestions, and recaps require internet access and an OpenRouter API key.

### Can it transcribe Zoom, Microsoft Teams, or Google Meet audio?

MeetingHelper captures system playback rather than connecting to a specific meeting platform or joining as a meeting bot. Audio played by a desktop meeting app or browser can feed the system-audio captions. It captures all system playback, so unrelated sounds may also be transcribed. Actual capture with your conferencing app, audio device, and permissions still needs a short test; see [validation limitations](docs/VALIDATION.md).

### Is MeetingHelper free and open source?

The app's source code is available under the MIT license. Local captions do not require an API key. Optional cloud AI usage is billed separately through your OpenRouter account.

### Does it record audio or save meeting transcripts?

It does not save audio recordings. Finalized captions and AI answers are saved locally as unencrypted chat history and can be exported as text. AI text sharing is optional and off by default; see [privacy and limitations](#privacy-and-limitations).

## Development

```sh
./scripts/test.sh
./scripts/chat-history-smoke-test.sh
./scripts/build-app.sh release
./scripts/package-app.sh
```

The package script creates a versioned ZIP, an installation DMG, and SHA-256 checksums in `dist/`. CI runs tests, the isolated history smoke test, and release packaging on a macOS 26 Apple Silicon runner. It uploads an Actions artifact. Pushing a version tag such as `v0.1.0` also publishes a GitHub Release with the DMG, ZIP, checksums, and generated release notes after all checks pass. See [release instructions](docs/BUILDING.md#automatic-github-releases).

- [Build, diagnostics, and distribution](docs/BUILDING.md)
- [Architecture](docs/IMPLEMENTATION.md)
- [Contributing](CONTRIBUTING.md)
- [Security reporting](SECURITY.md)

## License

[MIT](LICENSE) — including the source code and bundled logo assets.

Built by [CoreFixLab](https://corefixlab.com). Get in touch for customizations or other projects.
