# Security

MeetingHelper is an early-stage project. There is no promised security support period; fixes are developed on `main`.

For a suspected vulnerability, use the repository's **Security → Report a vulnerability** option if private reporting is enabled. If it is unavailable, open an issue requesting a private reporting channel without disclosing exploit details or sensitive data.

Include affected versions, reproduction steps using synthetic data, and the potential impact. Never include API keys or real meeting content.

The current design stores API keys in unencrypted local preferences and chat history in unencrypted local JSON. Optional AI sharing sends text through OpenRouter and its selected provider. These are documented limitations, not guarantees of confidential storage. See the [README](README.md) for the data flow and screen-sharing limitations.
