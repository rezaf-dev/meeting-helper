# User guide

Local live captions and text-based AI assistance for English meetings on Apple Silicon Macs. Built for macOS 26 or later, with no third-party runtime dependencies.

Microphone and system audio are transcribed on-device with Apple's SpeechTranscriber. Optional AI help sends text through OpenRouter to your selected model. It never uploads audio.

## Build and launch

Requires Swift 6.2+ and a macOS 26+ SDK. See [build requirements](BUILDING.md).

```sh
./scripts/build-app.sh
open dist/MeetingHelper.app
```

Launch the app bundle, rather than `swift run`, so macOS attributes microphone and system-audio permissions to MeetingHelper. The script creates a local ad-hoc signed app; it is not notarized for distribution. Rebuilding can cause macOS to ask for permissions again.

To explore the interface without recording:

```sh
open dist/MeetingHelper.app --args --demo
```

Open `Package.swift` in Xcode to edit the project. No package downloads or API key are required to build or use local captions.

## Use

1. Select Microphone, Meeting audio, or both. Meeting audio captures all system playback, not only one meeting app. Use headphones with both sources enabled to avoid duplicate speech.
2. Click **Start captions**. Allow microphone and system-audio recording access when requested; these are separate permissions. Meeting audio uses a Core Audio tap and does not request display capture. If meeting captions are silent while audio is playing, enable MeetingHelper under System Settings → Privacy & Security → Screen & System Audio Recording (the system-audio-only section where available), then quit and reopen the app. Settings includes a shortcut to that page. You can also disable Meeting audio for microphone-only captions. If one input fails to start, the other continues with a visible warning. The first start may download Apple's English speech assets.
3. Open **Float captions** to keep a small caption panel above normal app windows across desktops, Stage Manager, and eligible full-screen apps. It stays visible when you switch apps. Hide it from its **Hide** button or MeetingHelper's menu-bar menu; show it again from the same menu.
4. To enable AI: open Settings, save your **OpenRouter API key** in the app, and enable **Send meeting text through OpenRouter**. Usage is billed to your OpenRouter account. Default model: `google/gemini-3.1-flash-lite`. Use **Quick picks** for Gemini 3.1 Flash Lite, GPT-6 Luna, DeepSeek V4.1 Flash (October 17 snapshot), Gemini 3.5 Flash Lite, Qwen3.5 35B A3B, or Llama 3.3 70B Instruct. Each preset includes a short suggestion and a link to current details/pricing. Choose **Browse OpenRouter models → Load models** to search the current text-model catalog, or enter a model ID manually. Requests prefer lower-latency providers; latency is not guaranteed.
5. Write keywords in **What I want to say**, such as `need two more days; clarify scope; don't promise Friday`. The assistant uses this as your current goal, not as spoken meeting content. With **Update replies as I type** enabled, it requests a new reply after you pause typing for 900 ms. Choose **Apply note** to request a reply immediately. This also works before captions arrive.
6. Use **Explain that**, **What did they ask?**, **Help me reply**, or **Catch me up**. **Meeting context and draft** holds background facts and optional wording to polish. Automatic help can be disabled independently of live-note updates.
7. Chats save automatically on this Mac. Open **History** to search and read previous chats, or delete a chat with confirmation. **New chat** saves the current chat before resetting the workspace; stop captions first. The latest saved chat is restored on relaunch. Restarting captions resets the live transcript, while History retains all finalized captions and AI answers for the chat, including partial answers and request context.

## Saved profile

Open **Settings → Your profile** to save your role, background, English level, and communication preferences. For example: `I'm a product designer. Use short, polite English. Explain unfamiliar idioms. Don't make commitments on my behalf.` Nothing is prefilled about you.

The profile is saved automatically on this Mac and survives Clear, new meetings, and quitting the app. **Include my profile in AI requests** controls whether it is included. It is sent only when AI text sharing is also enabled. **Clear profile** removes the saved text.

Your profile sets enduring preferences; **What I want to say** sets your immediate aim and takes precedence for that reply. Profile edits cancel an outdated in-flight answer and take effect on the next request. They do not trigger an extra AI call.

A profile is capped at 2,000 characters and is included ahead of changing meeting text in the same request. This adds some input processing, not another network round trip. A random per-meeting session ID supports OpenRouter's provider stickiness and eligible prefix caching; caching and latency improvement depend on the selected provider and are not guaranteed.

Shortcuts: **⌘⇧L** start/stop, **⌘⇧E** explain, **⌘⇧R** draft reply, **⌘⇧H** show/hide floating captions, **⌘,** settings. These are app shortcuts, not system-wide hotkeys. The menu-bar Show/Hide command is also available while working in another app.

## Floating captions and screen sharing

**Settings → Floating captions → Request screen-capture exclusion** enables a legacy macOS exclusion hint. It is on by default, but it is best effort: modern screen-sharing apps can ignore it. MeetingHelper cannot guarantee that a visible caption panel is absent from full-display shares. Apple's current [documentation for the exclusion flag](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none) explicitly says not to rely on it to omit captured content.

For private captions, share one specific app window, or place captions on a different display from the one being shared. Check the recipient's view before relying on a particular setup. The panel's **Hide** button removes it from your screen too; use the menu-bar command to bring it back. There is no automatic claim that sharing is active or that the panel is invisible to others.

## Privacy and behavior

- AI is off by default. Local captions continue without an API key or network after Apple's assets are installed.
- Audio is never recorded to a file or sent to a cloud endpoint by this app.
- AI requests include recent finalized captions, meeting notes, your live intent, any enabled saved profile, any prior recap, and your rough reply. Text goes to OpenRouter and the selected upstream provider; their data policies apply.
- OpenRouter keys use provider-specific local app preferences. A previous OpenRouter Keychain entry is imported once if macOS permits access without a prompt; otherwise enter the key again. Keychain is no longer used for ongoing storage or authentication. Previous OpenAI keys are not reused or sent to OpenRouter. AI sharing must be enabled again after upgrading from the direct-OpenAI version.
- API keys are stored unencrypted in local app preferences. Remove key deletes the local value. Chats are saved as unencrypted JSON files in `~/Library/Application Support/MeetingHelper/Chats/`. They include finalized captions, AI answers and their request context, meeting notes, live intent, and drafts. History permanently deletes the selected local chat; exported copies are managed separately. Preferences, vocabulary, and the saved profile persist locally in UserDefaults. New chat and deleting a chat do not erase your profile. Example meetings are not saved. History starts with chats created in this version; previously discarded text cannot be recovered.
- “You” and “Meeting” identify audio sources, not individual people. The app does not identify remote speakers or automatically remove acoustic echo.
- Local captions and AI interpretations are displayed separately. Recognition and AI can make errors, especially in names, numbers, overlapping speech, and accented or noisy audio.

## Performance

Audio queues, retained captions, and AI request sizes are bounded. Automatic help waits for 1.2 seconds without changed provisional or final captions and starts no more than once every two seconds, with one request at a time. This is a transcript-based pause estimate, not audio-level voice activity detection. Continuous speech postpones automatic help; manual buttons remain available. Acknowledgments and your own answers do not trigger automatic requests. The model receives new speech separately from background context and the previous advice, and can return a silent no-update result. Automatic output is displayed only when complete and useful; canceled or empty updates leave the previous advice in place. Microphone-only sessions use manual help. Manual help cancels an older request. The app shows its own CPU/memory, caption age, dropped buffers, and first AI-text latency. Apple's speech service consumes additional resources outside this app's process.

Measure the combined workload in Activity Monitor during a real call and screen sharing. If audio falls behind, stop and restart with only the necessary audio source. No latency or accuracy guarantee has been established.

## Validation

```sh
./scripts/test.sh
```

Run `./scripts/chat-history-smoke-test.sh` for an isolated autosave, restart, new-chat, and deletion check using a temporary archive.

Tests cover chat persistence and deletion, transcript finalization, concurrent sources, bounded retention/context, SSE framing and failures, and text-only AI request construction. See [implementation notes](IMPLEMENTATION.md) for architecture and real-meeting checks.

## Logo assets

The blue speech-bubble and voice-bar logo is included in the Dock icon and app header. Editable vector: [Logo.svg](../Resources/Logo.svg). Raster master: [MeetingHelper.png](../Resources/MeetingHelper.png). Native macOS icon: [AppIcon.icns](../Resources/AppIcon.icns). `scripts/GenerateLogo.swift` renders the icon sizes from vector geometry.

The app declares `AppIcon.icns` in its bundle and explicitly assigns it to the running application's Dock tile at launch. Quit and reopen the updated app to load the icon fix. Keeping the app in the Dock after quitting is a separate macOS preference (Options → Keep in Dock).

To verify the actual local recognition pipeline without device capture, generate synthetic audio and run:

```sh
say -v Samantha -o .build/meeting-fixture.aiff 'Could you give us an estimate for the integration? I need to check the authentication changes first. Let us follow up tomorrow.'
./scripts/speech-smoke-test.sh "$PWD/.build/meeting-fixture.aiff"
```

This feeds the file at realtime speed through two independent production speech pipelines. It checks provisional updates, finalization, recognition of “estimate”, and dropped buffers. It needs access to Apple's local speech service and may download language assets. It makes no AI API calls.

### Copying and exporting sessions

**Copy transcript** copies the complete finalized transcript for the current chat, including captions beyond the live view’s 500-segment limit and earlier caption recordings in the same chat. **Export text** saves that transcript as a UTF-8 `.txt` file. Unfinished speech hypotheses are excluded until finalized.

In **AI help**, **Copy all** copies every AI answer, including partial replies; the save icon exports them. Each individual answer has its own **Copy** button.

In **History**, choose a chat and use **Copy** or **Export…** → **Full transcript**, **All AI answers**, or **Full session**. Full session includes the transcript, AI answers, notes, draft, and live intent. These controls also work with the current chat before the latest autosave finishes.

### Reading AI answers

The AI pane can expand by dragging the divider. It follows incoming text while you are at the bottom; scrolling up pauses following so you can read and select text. Scroll back to the bottom or choose **Latest answer** to resume. **Hide note** gives the answer more height without clearing your note; **Show note** restores the editor. The action buttons remain available in both modes.

### English level and short answers

Settings → **English help** saves your English comfort level (Basic, Intermediate, Advanced), answer length (Brief, Balanced, Detailed), and whether to explain important things only. Defaults are **Intermediate + Brief + important things only + Speaking hints**: assume everyday English is understood, focus on consequential jargon/idioms or questions, offer vocabulary and a reusable sentence pattern with blanks for speaking, and avoid headings or repeated transcript. Brief usually targets 35 words (45 for Explain, 80 for Recap); these are prompt instructions, not a guarantee of exact model output length. These choices apply to the next request, even when profile inclusion is off, and override conflicting level/verbosity in the saved profile. They do not change speech recognition or add an AI call.

Choose **Settings → English help → Speaking support → Full replies** when you want complete suggested wording. **Speaking hints** applies to live help, Help me reply, and live-note updates; Explain, Question, and Recap keep their respective purposes. Example hint: “rough estimate” = approximate amount; pattern: “Before I estimate [work], I need [detail].”
