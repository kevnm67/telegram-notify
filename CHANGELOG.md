# Changelog

All notable changes to this orb are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the orb uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

### Added

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

## [0.1.0] - 2026-02-21

### Initial release

- Initial `notify-failure` command sending Telegram messages with error
  output from the CircleCI v1.1 API.
