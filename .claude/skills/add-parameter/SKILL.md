---
name: add-parameter
description: >
  Add or change an orb parameter consistently across the generated command
  files, the TELEGRAM_NOTIFY_* env mapping, notify.sh, bats tests, README and
  wiki. Use when asked to "add a parameter", "expose an option", or when a
  review flags parameter drift.
---

# Add a parameter

The three command files are generated from one manifest; never edit them by hand.

1. Add the row to `PARAMS` in `scripts/dev/generate-commands.py`
   (`name`, type, default, description) and its `TELEGRAM_NOTIFY_*` name in `ENV_MAP`.
2. `make generate-commands` — rewrites `src/commands/*.yml`.
3. Read the env var in `src/scripts/notify.sh` (`tn_is_true` for booleans; defaults via `${VAR:-}`).
4. Add bats coverage in `tests/notify.bats`; add the env var to the `unset` list in
   `tests/test_helper/common.bash`.
5. Document: README parameter table, `wiki/Installation.md` table, `CHANGELOG.md`.
6. `make lint test validate`.

Names are `snake_case`; booleans arrive as `1`/`0` in CircleCI.
