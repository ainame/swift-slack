# Upstream snapshots and review coverage

The submodule gitlinks are the generation inputs. This document records semantic
review coverage separately: a pinned commit alone does not prove SDK parity.

## Baseline recorded on 2026-10-03

| Source | Pinned commit | Role |
| --- | --- | --- |
| [java-slack-sdk](https://github.com/slackapi/java-slack-sdk) | [`dbe498ce0a2f0ed068b4bd7028ce31d22c91998d`](https://github.com/slackapi/java-slack-sdk/commit/dbe498ce0a2f0ed068b4bd7028ce31d22c91998d) | Observed response/event fixtures and handwritten model reference |
| [slack-api-ref](https://github.com/slack-ruby/slack-api-ref) | [`4f0934e301e9a9a15883ea54fbf8a22efb8e8fc9`](https://github.com/slack-ruby/slack-api-ref/commit/4f0934e301e9a9a15883ea54fbf8a22efb8e8fc9) | Method definitions, request arguments, and schema constraints |

These pins were read from `origin/main` while preparing the automation migration.
No new vendor update, generation pass, or full upstream parity audit was performed
to establish this baseline. Existing coverage follows the fixture policy and
ownership rules in `AGENTS.md`.

## Maintaining this record

For each reviewed sync, replace the snapshot table with the new gitlinks and
record the review date, previous SHAs, covered upstream areas, implemented changes,
intentional exclusions, and unresolved gaps. Include the sync PR reference once
available. A no-op result requires live upstream access and comparison against
current `origin/main`, not just an unchanged generated tree.

Review coverage applies to that vendor delta. It does not imply complete historical
parity with the Java SDK, Slack reference, or live Slack service.
