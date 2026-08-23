# telegram-notify — project guide for Claude Code

CircleCI orb (`kevnm67/telegram-notify`) sending Telegram notifications from jobs.
Bash 3.2+ and curl only; jq/python3 optional. Read `AGENTS.md` for the file map.

## Non-negotiables

- `src/scripts/notify.sh` is failure-safe: exit 0 unless `TELEGRAM_NOTIFY_FAIL_ON_ERROR` is true.
- Everything interpolated into Telegram HTML goes through `tn_html_escape`, except `custom_message` /
  `mentions` / `custom_body` markup (documented as trusted).
- CircleCI renders boolean params as `1`/`0` → always test with `tn_is_true`.
- bash ≥ 5.2 `patsub_replacement` is disabled at the top of the script; never use `&` in `${x//a/b}`
  replacements elsewhere.
- Orb component and parameter names are `snake_case`. Pipeline values (`<< pipeline.* >>`) are NOT
  allowed inside orb source.
- No inline shell in CI YAML: scripts live in `scripts/ci/` with `set -euo pipefail`.
- Parameters exist in three command files — they are generated from
  `scripts/dev/generate-commands.py` (see `/add-parameter`); never hand-edit one of them alone.

## Commands

```bash
make lint            # shellcheck + yamllint + markdownlint + orb pack/validate
make test            # bats (enforced assertions — helper restores errexit after sourcing)
make test-bash32     # same suite in the bash:3.2 Alpine image (no jq/python3) via Docker
make coverage        # kcov line coverage (Docker on macOS)
make integration     # mock Telegram + stubbed CircleCI/Anthropic APIs, all templates
make validate        # circleci orb pack + validate
make generate-commands
make publish-dev TAG=alpha
```

## Testing model

- Unit: `tests/notify.bats` sources the script and asserts on the recorded `curl` argv
  (`$MOCK_CURL_LOG`); `tests/test_helper/mock_bin/curl` answers from `MOCK_*` variables.
- Integration (CI `test_deploy` workflow): `scripts/ci/mock-telegram-server.py` (:8089),
  `scripts/ci/stub-circleci-api.sh` (:8090 CircleCI, :8091 Anthropic), assertions in
  `scripts/ci/assert-integration-templates.sh`.
- Live: pipeline parameter `live_test=true` runs the published `@dev:alpha` orb against real
  Telegram (context `ci_notify`). See `/live-test`.

## Release

`main` → `@dev:alpha` automatically. Production: update `CHANGELOG.md`, tag `vX.Y.Z` (see `/orb-release`).
