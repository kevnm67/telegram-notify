# AGENTS.md — telegram-notify orb

Guidance for AI agents and new contributors. Keep this file in sync with
`README.md` when parameters, files or workflows change.

## What this is

A CircleCI orb (`kevnm67/telegram-notify`) that sends Telegram messages
from jobs: on failure (with failed-step output from the CircleCI API), on
success, or always. Bash + curl only.

## Layout

| Path | Purpose |
| ------ | --------- |
| `src/@orb.yml` | Orb metadata |
| `src/commands/notify.yml` | Event-driven command; the only place parameters → env vars are mapped |
| `src/commands/notify_failure.yml`, `notify_success.yml` | Thin wrappers over `notify` |
| `src/scripts/notify.sh` | All logic. `tn_*` functions; `main` guarded by `TELEGRAM_NOTIFY_NO_MAIN` |
| `src/scripts/record_failure.sh` | `on_fail` marker used by `event: always` |
| `src/examples/*.yml` | Registry usage examples (`usage:` must be valid 2.1 config) |
| `tests/notify.bats` | Unit suite; `tests/test_helper/mock_bin/curl` is the curl double |
| `scripts/ci/*.sh` | Everything CI runs — no inline shell in YAML |
| `.circleci/config.yml` | Setup workflow (lint/pack/review/shellcheck/unit_tests → continue) |
| `.circleci/test-deploy.yml` | Integration jobs with the injected orb + publish |
| `docs/architecture/*.d2` | Diagram source; render with `make diagrams` (never Mermaid/ASCII) |
| `wiki/` | Synced to the GitHub wiki by `wiki-sync.yml` |

## Rules

- Orb parameter/command names are `snake_case` (`orb-tools/review` RC010).
- Scripts stay failure-safe: exit 0 unless `TELEGRAM_NOTIFY_FAIL_ON_ERROR=true`.
- Never log tokens. Escape anything interpolated into the message except
  `custom_message`/`mentions` (documented as trusted).
- Every new parameter: add to all three command files, `notify.sh`, a bats
  test, README parameter table, wiki Installation page, CHANGELOG.
- Versions (orbs, images, hooks, actions) are verified live, pinned, and
  bumped by Renovate — don't hand-edit to guessed versions.

## Commands

```bash
make lint          # shellcheck + yamllint + markdownlint + orb validate
make test          # bats
make coverage      # kcov (Docker on macOS)
make validate      # circleci orb pack + validate
make publish-dev TAG=alpha
```

## Testing strategy

- Unit: source `notify.sh` with `TELEGRAM_NOTIFY_NO_MAIN=1`, call `tn_*`
  functions, assert on the recorded `curl` arguments (`$MOCK_CURL_LOG`).
- Integration (CI only): `scripts/ci/mock-telegram-server.py` on `:8089`
  receives real orb command output; `assert-mock-received.sh` checks it.
- Failure path: `scripts/ci/simulate-failure-notification.sh` stubs the
  CircleCI API on `:8090` so the error-output branch runs without failing
  the job.

## Release

`main` → `@dev:alpha`; tag `vX.Y.Z` → production publish (context
`orb-publishing`). Update `CHANGELOG.md` before tagging.
