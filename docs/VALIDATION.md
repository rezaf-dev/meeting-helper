# Validation — 27 October 2026

Environment: Apple Silicon Mac, macOS 27.0.1, Apple Swift 6.4 Command Line Tools.

## Open-source preparation checks

On October 27, 2026, using the environment above:

- All 34 tests in seven Swift Testing suites passed without live AI calls or device capture, both in the workspace and in a clean temporary source copy. Release packaging also passed from that clean copy.
- The isolated history smoke test passed transcript/export retention, autosave, restart restoration, new chat, and permanent deletion checks.
- The release app compiled, its Info.plist passed validation, and its ad-hoc signature verified.
- Versioned ZIP packaging passed checksum validation; the extracted app signature also verified.
- The installation DMG passed disk-image and SHA-256 verification. A read-only mount confirmed the Applications shortcut, bundled MIT license, and app signature; the image was then ejected.
- Shell scripts and workflow YAML passed syntax checks; local documentation links resolved.
- A pattern scan of tracked files found no matching API keys or private-key headers. This is a limited scan, not a guarantee that no sensitive content exists.

The local restricted command sandbox blocked Apple's release dSYM generator; release packaging succeeded with normal host access. The Command Line Tools build emitted missing developer-framework search-path warnings, and the diagnostic compile reported macOS 27 deprecations for APIs retained for macOS 26 compatibility. These warnings did not fail the checks.

GitHub Actions execution will be verified after the workflow is pushed. Interactive capture, real AI requests, and notarization remain outside these automated checks.

## Verified

- The native application compiles and opens on this Mac.
- Desktop UI inspected in the actual application: empty state, example transcript, assistance pane, settings sheet, and floating caption window. AI is off by default; the settings sheet reports that no API key is saved.
- Version 0.2 adds the vector logo to the header and native app icon, OpenRouter settings, and the live intent editor. Typed synthetic keywords were accepted with sharing off; Apply note led to setup without uploading text.
- The production model-catalog loader fetched OpenRouter's public API successfully, found 464 text-compatible models at verification time, and confirmed `google/gemini-3.1-flash-lite` was present. No credential or meeting content was sent for this check.
- Seventeen automated tests pass: source-isolated finalization, replacement of partial results, duplicate final updates, late hypotheses, bounded chronological transcript/context, text-only OpenRouter prompt construction, separate live intent, model-catalog filtering, SSE event framing, output limits, fragmented streamed HTTP responses, partial disconnects, authorization and credit errors, provider failures, cancellation, bounded stable profile messages, and omission of empty/excluded profiles.
- The production local speech pipeline was compiled into a file-only diagnostic. A 7.16-second synthetic English recording was fed at realtime speed into two independent pipelines. Both produced the expected sentences, including “estimate”, “integration”, and “authentication”. There were 60 provisional updates across both pipelines and zero dropped buffers. Finalization completed successfully. This was also checked with the accuracy-preferred default (without `fastResults`).
- The speech diagnostic uses only the synthetic file, not microphone/system capture or an AI endpoint. It needed normal macOS access to Apple's local speech service; the restricted command sandbox could not enumerate the available English locale.
- The version 0.4 native panel configuration probe passed for floating level, non-hiding behavior on app deactivation, all-Spaces/all-apps/full-screen eligibility flags, and switching the legacy capture hint on and off. It intentionally does not claim to verify screen-share exclusion.

- Version 0.5 compiles and signs with a Core Audio audio-only tap in place of ScreenCaptureKit. The 17 existing tests pass. A file-free buffer probe exercised the production HAL handoff with planar and interleaved 48 kHz stereo samples; all samples remained intact after the source storage was overwritten. No microphone, process tap, or cloud request was started by that probe.
- Partial-source startup was reviewed: selected inputs start independently, failed pipelines are canceled, successful inputs are named in the status, and complete failure releases capture resources. Actual permission-denial and mixed-success behavior still need an interactive check.

- Version 0.6's production UI was checked in a separate native app fixture using synthetic text and no recorder/API calls. Appending and streaming paragraphs stayed at scrollbar position 1 while following. Scrolling upward showed Latest answer and held the same visible earlier paragraphs through 20 appended updates. Latest answer returned the scrollbar to 1 and subsequent streaming continued following. Manually scrolling back to the bottom also removed the jump button and resumed following. Hide note removed the editor/context controls and enlarged the answer viewport while leaving all AI actions available. The AI pane occupied about half of the 1,180-point window instead of the old 440-point cap.

- Version 0.6.1's six built-in quick picks were checked against OpenRouter's public catalog on October 27, 2026: all exact IDs existed and accepted text input/output. No API key or meeting data was sent. This verifies catalog presence, not account access, measured speed, or completion quality.

- Version 0.7 adds persistent English level, answer length, and important-only preferences. Nineteen tests pass, including prompt checks for the intermediate/brief default without a saved profile and action-specific preferences overriding old profile verbosity. These checks verify request construction; they do not establish that every hosted model will obey the requested length or focus.

## Not yet verified

- Live microphone and Core Audio tap device capture after the user grants macOS permissions.
- A real OpenRouter completion, account access to the configured model, billing, or actual AI latency: no live API request was made during validation. Network streaming tests use URLProtocol simulation.
- Recognition accuracy for the user's accents, overlapping speakers, noisy environments, or Bluetooth audio changes.
- Sustained performance while Zoom/Teams, screen sharing, and normal work apps are active. The app's metrics exclude Apple's separate speech-service process.
- Floating-panel visibility in every third-party full-screen app and exclusion from actual screen-sharing tools. The legacy exclusion hint is explicitly not a capture-prevention guarantee.

Before relying on the app in a meeting, run a short call with headphones, grant capture permissions, add the API key in Settings if desired, and observe caption/AI delay and Activity Monitor. The synthetic test is a functional check, not an accent benchmark or a latency guarantee.
