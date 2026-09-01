---
name: add-parameter
description: >
  Add or change a telegram-notify orb parameter consistently across the
  generated command files, the TELEGRAM_NOTIFY_* env mapping, notify.sh, the
  bats suite, README and wiki. Use when asked to "add a parameter", "expose an
  option", or when a review flags parameter drift between the three commands.
allowed-tools: Bash, Read, Edit, Grep
---

# Add a parameter

`src/commands/notify.yml`, `notify_failure.yml` and `notify_success.yml` are
**generated**. Editing one by hand drifts the other two and fails orb review.

Work the list in order; each step has its own check:

- [ ] 1. Add the row to `PARAMS` in `scripts/dev/generate-commands.py` (name,
      type, default, description) and its variable name to `ENV_MAP`.
- [ ] 2. `make generate-commands`, then confirm the parameter landed in all
      three files: `grep -c '<name>:' src/commands/*.yml`
- [ ] 3. Read the new variable in `src/scripts/notify.sh`. Booleans go through
      `tn_is_true`; every read needs a default — `"${TELEGRAM_NOTIFY_X:-}"`.
- [ ] 4. Add a bats case in `tests/notify.bats` asserting on the recorded curl
      argv, and add the variable to the reset list in
      `tests/test_helper/common.bash`.
- [ ] 5. Document it in the README parameter table, `wiki/Installation.md`, and
      the `[Unreleased]` section of `CHANGELOG.md`.
- [ ] 6. `make lint test validate` — all three, and iterate until green.

## Gotchas

- Names are `snake_case`; `orb-tools/review` RC010 fails the build on
  kebab-case.
- CircleCI renders a boolean parameter as `1` / `0`, never `true` / `false`, so
  a plain `[[ "$X" == "true" ]]` is always false in CI. Use `tn_is_true`.
- Anything interpolated into the message must pass through `tn_html_escape`.
  Only `custom_message`, `mentions` and `custom_body` are documented as trusted
  markup; a new parameter is not trusted unless you document it as such.
- Must work on bash 3.2 without `jq` or `python3`: no associative arrays, no
  `${var,,}`, no `mapfile`, and every JSON read needs a grep/sed/awk fallback.
  `make test-bash32` is the check, and it only runs under Docker.
- Skipping step 4 is the usual cause of a value leaking between tests — the
  helper only clears what is listed in it.
