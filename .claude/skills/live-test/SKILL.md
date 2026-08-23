---
name: live-test
description: >
  Trigger the telegram-notify live dogfood workflow on CircleCI (real Telegram,
  real CircleCI/Anthropic APIs, published @dev:alpha orb) and report each
  job's Telegram step output. Use when asked to "live test", "dogfood",
  "send a real notification", or after a dev publish to verify it end to end.
---

# Live test

1. Trigger (branch defaults to `main`; pass another branch to test unmerged config):

   ```bash
   T=$(grep -o 'token: .*' ~/.circleci/cli.yml | cut -d' ' -f2)
   curl -s -X POST -H "Circle-Token: $T" -H "Content-Type: application/json" \
     https://circleci.com/api/v2/project/gh/kevnm67/telegram-notify/pipeline \
     -d '{"branch":"main","parameters":{"live_test":true}}' | jq '{number,id}'
   ```

2. Poll `GET /api/v2/pipeline/{id}/workflow` until the `live_test` workflow is not
   `running`, then `GET /api/v2/workflow/{wf}/job` for job numbers.

3. For every job, fetch the v1.1 build (`/api/v1.1/project/github/kevnm67/telegram-notify/{n}`),
   find steps named `Telegram notification*`, download their `output_url` and print the
   `[telegram-notify]` lines. Expected: `Notification sent (...)` in every job;
   `live_failure` and `live_ai_summary` are red **on purpose**.

4. Report a table: job · template · status · delivered? Ask the user to confirm the
   messages on their phone when rendering matters (buttons, AI section).

Context `ci_notify` holds `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `CIRCLE_TOKEN`,
`ANTHROPIC_API_KEY`. Never print their values.
