# Development

## Contents

- [Tooling](#tooling)
- [Tests](#tests)
- [Coverage](#coverage)
- [CI pipeline](#ci-pipeline)
- [Releasing](#releasing)
- [Conventions](#conventions)

## Tooling

```bash
make setup      # brew: bats-core shellcheck circleci d2; pip: pre-commit
make lint       # shellcheck + yamllint + markdownlint + orb pack/validate
make test       # bats
make test-bash32  # same suite on bash 3.2 without jq/python3 (Docker)
make integration  # all templates vs mock Telegram + stubbed CircleCI/Anthropic
make coverage   # kcov (runs in Docker on macOS)
make generate-commands  # regenerate src/commands/*.yml from the parameter manifest
make diagrams   # render docs/architecture/*.d2 → svg + png
```

Pre-commit runs shellcheck, yamllint, markdownlint, orb validate and the
bats suite on relevant changes.

## Tests

- `tests/notify.bats` sources `src/scripts/notify.sh` with
  `TELEGRAM_NOTIFY_NO_MAIN=1` and exercises each `tn_*` function plus
  `main` end-to-end. The helper re-enables `set -e` after sourcing (the
  script runs `set +e`), otherwise bare assertions would be vacuous.
- Tests needing jq or python3 call `require_json_tool` and are skipped on
  the bash 3.2 image; everything else must pass there too.
- `tests/test_helper/mock_bin/curl` shadows `curl`, records arguments to
  `$MOCK_CURL_LOG`, and answers from `MOCK_HTTP_CODE`,
  `MOCK_TELEGRAM_BODY`, `MOCK_CIRCLE_BUILD_JSON`, `MOCK_STEP_OUTPUT`,
  `MOCK_CURL_EXIT`.

## Coverage

`scripts/ci/run-unit-tests.sh --coverage` wraps bats in kcov
(`--include-path=src/scripts`) and writes `coverage/bats/cobertura.xml`,
which the `unit_tests` job publishes to qlty with `add_prefix: src/scripts`.
kcov comes from apt on Ubuntu 22.04, hence `cimg/base:current-22.04`.

## CI pipeline

`.circleci/config.yml` (setup workflow):

1. `orb-tools/lint` — yamllint on `src/`
2. `orb-tools/pack` — pack `src/` into one orb
3. `orb-tools/review` — style rules (descriptions, snake_case, …)
4. `shellcheck/check` — all `*.sh`
5. `unit_tests` — bats + kcov → qlty; `unit_tests_bash32` — bash 3.2, no jq/python3
6. `orb-tools/continue` → `.circleci/test-deploy.yml`

`test-deploy.yml` injects the packed orb and runs:

| Job | Exercises |
| ----- | ----------- |
| `integration_test_success` | `notify_success`, custom message, links |
| `integration_test_always` | `notify` `event: always`, topic, silent, mentions |
| `integration_test_dry_run` | nothing is sent |
| `integration_test_failure_path` | error output, duration, buttons and `attach_log` against stubbed CircleCI APIs |
| `integration_test_templates` | `test_summary`, `insights`, `ai_summary` (stubbed Anthropic), `custom`, branch filter |

All jobs target `scripts/ci/mock-telegram-server.py` on `127.0.0.1:8089`;
`scripts/ci/stub-circleci-api.sh` serves CircleCI (:8090) and Anthropic (:8091).
`scripts/ci/assert-integration-templates.sh` holds the per-template assertions.

Live dogfood: trigger a pipeline with `{"parameters":{"live_test":true}}` to
run `live_success`, `live_failure`, `live_ai_summary`, `live_test_summary`,
`live_insights`, `live_custom` and `live_always_post_step` with the published
`@dev:alpha` orb against real Telegram (context `ci_notify`).
Then `publish_dev` (`main`) or `publish_production` (`v*` tags).

## Releasing

1. Update `CHANGELOG.md`.
2. Merge to `main` → `kevnm67/telegram-notify@dev:alpha` is published.
3. `git tag vX.Y.Z && git push origin vX.Y.Z` → production publish.

## Conventions

- Orb components and parameters: `snake_case`.
- No inline shell in CI YAML — everything lives in `scripts/ci/`.
- Diagrams: d2 source in `docs/architecture/`, rendered SVG/PNG committed
  and checked by `make verify-diagrams`.
- Conventional commits; squash merges; Renovate keeps versions current.
