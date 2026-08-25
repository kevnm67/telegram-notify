# Changelog

All notable changes to this orb are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the orb uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Templates: `test_summary` (pass/fail/skip counts, runtime, failed test names
  from the CircleCI tests API), `insights` (workflow success rate, p95
  duration, MTTR, throughput, flaky-test count), `ai_summary` (Claude root
  cause, likely fix and copy-paste prompt), `deploy` (release card) and
  `custom` (`custom_body` with `{{ENV_VAR}}` substitution).
- Inline keyboard buttons (`buttons`) for View build / Workflow / Pull request;
  repository, branch/tag, job and PR are hyperlinked; `⏱ Duration` from the v2
  job endpoint (`include_duration`).
- `attach_log` uploads the failed step's full output as a document.
- `branch_pattern`, `tag_pattern`, `invert_match` filters.
- Parameters `anthropic_api_key`, `ai_model`, `ai_max_tokens`,
  `max_failed_tests`, `insights_window`, `workflow_name`, `deploy_environment`.
- bash 3.2 / no-jq / no-python3 compatibility job (`unit_tests_bash32`) and
  grep/sed/awk fallbacks for every JSON read.
- Integration job `integration_test_templates` against stubbed CircleCI and
  Anthropic APIs; live dogfood jobs for every template.
- Project Claude assets: `.claude/CLAUDE.md`, hooks (post-edit checks,
  commit gate), `orb-reviewer` agent, `live-test`, `orb-release` and
  `add-parameter` skills; `scripts/dev/generate-commands.py` keeps the three
  command files in sync.

- `notify` command with `event: failure | success | always`.
- `notify_success` command.
- Parameters: `bot_token`, `circle_token`, `custom_message`, `mentions`,
  `thread_id`, `silent`, `dry_run`, `fail_on_error`, `vcs_type`, `api_base`,
  `step_name`; `chat_id` falls back to `TELEGRAM_CHAT_ID`.
- `👤 Triggered by` line (from `CIRCLE_USERNAME`).
- bats unit suite (40 tests) with kcov coverage published to qlty.
- Four integration jobs exercising the packed orb against a local Telegram
  API double.
- Renovate grouping, pre-commit hooks, Makefile, d2 architecture diagram,
  wiki, GitHub caller workflows (Claude review/fix, labeler, merge-on-green,
  PR summary, label sync, wiki sync, repo audit).

### Changed

- **Renamed** from `ci-failure-notifier` to `telegram-notify`
  (`kevnm67/telegram-notify`); command `notify-failure` is now
  `notify_failure` (snake_case, per `orb-tools/review`).
- Telegram request is sent as a URL-encoded form instead of hand-built JSON,
  fixing messages containing quotes or newlines.
- Failed step detection uses the action's `failed`/`status` fields (via `jq`
  when available) instead of the first `output_url` in the payload.
- Error block and total message are truncated independently so `<pre>` is
  never left open; ANSI codes are stripped.
- All interpolated job metadata is HTML-escaped.
- CI rebuilt on the CircleCI Orb Development Kit (`orb-tools@12.5.0`) with
  setup → `test-deploy` continuation, dev publish on `main`, production
  publish on `vX.Y.Z` tags.

### Fixed

- `ai_summary` sends the request body from a file and strips C0 control
  bytes from the log so unusual step output cannot produce invalid JSON.
- The bats helper now restores `errexit` after sourcing `notify.sh` — previously
  every bare `[[ ]]` assertion in the suite was silently vacuous.
- `tn_extract_messages` no longer inserts blank lines between step messages.
- Escaped-slash normalisation and failed-action selection work on bash 3.2
  without jq.

## [0.1.0] - 2026-02-21

### Initial release

- Initial `notify-failure` command sending Telegram messages with error
  output from the CircleCI v1.1 API.
