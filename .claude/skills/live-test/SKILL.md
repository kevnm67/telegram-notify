---
name: live-test
description: >
  Dogfood the published kevnm67/telegram-notify@dev:alpha orb against the real
  Telegram, CircleCI and Anthropic APIs by triggering the live_test workflow,
  then report each template's Telegram step output. Use when asked to "live
  test", "dogfood", "send a real notification", or to verify a dev publish
  end to end before tagging a release.
allowed-tools: Bash, Read, Grep
---

# Live test

Runs seven jobs in the `live_test` workflow (`notify_success`, `notify_failure`,
one per template, and `event: always` as a post-step) against context
`ci_notify`.

## Run it

```bash
scripts/dev/live-test.sh          # branch defaults to main
scripts/dev/live-test.sh my-branch
```

The script triggers the pipeline, polls the workflow to completion, and prints
every `Telegram notification*` step's output per job. Do not hand-roll the curl
calls — the script keeps the API token out of `ps` and out of the transcript.

## Report

One row per job. A job is a PASS only when its step output shows a `200` /
`"ok":true` send **and** the message is visible in the chat:

| Job | Template | Step output | In chat |
| --- | --- | --- | --- |
| `live_failure` | basic | `sent (200)` | ✅ |

## Gotchas

- `live_failure` and `live_ai_summary` are **red on purpose** — the job fails so
  the `on_fail` path runs. A red workflow is not a failed live test.
- The orb under test is the last `main` publish, not the working tree. If `src/`
  changed since, merge and let `publish_dev` run before believing the result.
- `ai_summary` silently degrades to the basic message when the Anthropic key is
  absent from `ci_notify`; an empty AI section means a missing key, not a bug.
- `insights` needs history — on a project with few runs it renders "no data",
  and that is a pass.
- Trigger with the pipeline parameter, never by pushing: the workflow is gated
  on `when: << pipeline.parameters.live_test >>` and never runs on an ordinary
  push.
