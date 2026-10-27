# Contributing

Bug reports, documentation fixes, and focused pull requests are welcome.

Build requirements and commands are in [BUILDING.md](docs/BUILDING.md). Open `Package.swift` in Xcode or use the command-line scripts. Keep changes small, explain the user-visible behavior, and include the checks you ran in your pull request.

Before submitting:

```sh
./scripts/test.sh
./scripts/chat-history-smoke-test.sh
./scripts/build-app.sh release
```

Add tests for changes to transcript handling, persistence, request construction, streaming, or automatic assistance. UI, device capture, permission, and recognition changes also need manual checks; say which hardware and macOS version you tested and which checks remain undone.

Use synthetic meeting content in tests and reports. Do not attach real transcripts, profiles, API keys, exported preferences, or recordings. For a bug, include the app/macOS versions, steps to reproduce, expected and actual behavior, and sanitized diagnostics. Report security issues through [SECURITY.md](SECURITY.md).

Contributions are provided under this repository's [MIT license](LICENSE).
