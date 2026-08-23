# Roadmap

Groomed 2026-08-23 from discovery (Telegram Bot API, CircleCI API v2 / Insights,
circleci/slack orb parity review, test-gap audit). Status legend: ✅ shipped · 🔄 in progress · ⏳ planned.

## Contents

- [v0.0.1 — first production release](#v001--first-production-release)
- [v0.1 — candidates](#v01--candidates)
- [Explicitly out of scope](#explicitly-out-of-scope)

## v0.0.1 — first production release

| # | Item | Why | Status |
| --- | ------ | ----- | -------- |
| 1 | Inline keyboard buttons (`buttons`) for View build / View workflow / Pull request | Tap targets beat text links on mobile | ✅ |
| 2 | Hyperlinked commit / branch / PR in the metadata block | Every identifier jumps to the VCS page | ✅ |
| 3 | Job duration + PR number in the metadata block (v2 job details) | Context without opening CircleCI | ✅ |
| 4 | `branch_pattern` / `tag_pattern` / `invert_match` filters | Parity with circleci/slack; quiet feature branches | ✅ |
| 5 | `template: test_summary` — pass/fail/skip counts, runtime, top failed tests | "Post test results summaries (formatted)" | ✅ |
| 6 | `template: insights` — workflow success rate, p95 duration, MTTR, flaky tests | "CI insights/metrics" | ✅ |
| 7 | `template: ai_summary` — Claude summary + likely fix + copy-paste prompt | "Failures + agentic summary and prompt to fix" | ✅ |
| 8 | `template: deploy` — tagged-release success card | Parity with slack `success_tagged_deploy_1` | ✅ |
| 9 | `template: custom` with `{{VAR}}` substitution (`custom_body`) | Fully custom formatting without forking the orb | ✅ |
| 10 | `attach_log` — upload the failed step's full output as a document | 4096-char messages can't hold real logs | ✅ |
| 11 | bash 3.2 + jq-less + python-less compatibility job (`bash:3.2` image) | macOS executors and slim images | ✅ |
| 12 | Live dogfood jobs for every template | Real Telegram, real CircleCI APIs | ✅ |
| 13 | Project-level Claude assets (`.claude/`: CLAUDE.md, settings hooks, agent, skills) | Faster, safer iteration in this repo | ✅ |
| 14 | README / wiki / examples / CHANGELOG refresh, tag `v0.0.1` | Release | ✅ |

## v0.1 — candidates

| Item | Notes |
| ------ | ------- |
| `edit_in_place` — send "⏳ running" at job start and edit to the final state | needs `editMessageText` + message_id persisted in the workspace |
| `pin_on_failure` / `setMessageReaction` | cheap polish once message ids are kept |
| Per-test flakiness annotation in `test_summary` | cross-reference `/insights/{slug}/flaky-tests` |
| Markdown→HTML converter for `custom_body` | authoring ergonomics |
| Telegram topics auto-routing by branch | map branch patterns to `thread_id`s |
| Windows (PowerShell) executor support | currently bash-only |

## Explicitly out of scope

- Slack/Discord/Teams targets — single-purpose orb by design.
- Storing message ids for threading across jobs — needs a workspace contract; revisit with `edit_in_place`.
