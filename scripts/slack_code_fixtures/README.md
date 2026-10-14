# Slack Code regression payloads

These are **synthetic downstream swift-slack regression payloads**, not recordings
from Slack or upstream java-slack-sdk fixtures. Field contracts and source URLs
live in `../slack_code_schemas.yml`.

- `ConversationsInfoResponse.json` exercises documented code channel properties.
- `AppManifest.json` exercises the documented code channel manifest feature.
- `CodeChannelActionPayload.json` tests lossless arbitrary JSON handling only.
  Its `synthetic_*` keys deliberately make no claim about Slack's action payload.
  Slack documents the event's existence but publishes no payload schema.

The generated fixture decode check includes the opaque action payload. Dedicated
Swift tests verify the supplemented response and manifest fields, re-encoding,
legacy payloads, event equality, and typed router dispatch.
