# Installation

## Contents

- [1. Telegram bot](#1-telegram-bot)
- [2. CircleCI context](#2-circleci-context)
- [3. Add the orb](#3-add-the-orb)
- [4. Parameters](#4-parameters)
- [5. Templates](#5-templates)
- [6. Verify with dry run](#6-verify-with-dry-run)

## 1. Telegram bot

1. Talk to [@BotFather](https://t.me/botfather): `/newbot`, copy the token.
2. Add the bot to the target group/channel (channels: make it an admin).
3. Get the chat ID from `https://api.telegram.org/bot<TOKEN>/getUpdates`
   after sending a message. Group/channel IDs are negative
   (`-100…`). For forum groups, the topic ID is `message_thread_id`.

## 2. CircleCI context

| Variable | Required | Notes |
| ---------- | ---------- | ------- |
| `TELEGRAM_BOT_TOKEN` | yes | from BotFather |
| `TELEGRAM_CHAT_ID` | no | default chat when `chat_id` is omitted |
| `CIRCLE_TOKEN` | no | read-only API token; enables error output, duration, `test_summary`, `insights` |
| `ANTHROPIC_API_KEY` | no | only for `template: ai_summary` |

Attach the context to every job that uses the orb.

## 3. Add the orb

```yaml
version: 2.1
orbs:
  telegram-notify: kevnm67/telegram-notify@1.0.0

jobs:
  build:
    docker:
      - image: cimg/base:current
    steps:
      - checkout
      - run: make build
      - telegram-notify/notify_failure: {}   # uses TELEGRAM_CHAT_ID

workflows:
  build:
    jobs:
      - build:
          context: telegram
```

Or as a workflow-level post-step that reports every outcome:

```yaml
      - build:
          context: telegram
          post-steps:
            - telegram-notify/notify:
                event: always
```

## 4. Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `event` | `failure` | `failure` / `success` / `always` (`notify` only) |
| `template` | `basic` | `basic`, `test_summary`, `insights`, `ai_summary`, `deploy`, `custom` |
| `chat_id` | `""` | falls back to `$TELEGRAM_CHAT_ID` |
| `bot_token` | `TELEGRAM_BOT_TOKEN` | env var **name** |
| `circle_token` | `CIRCLE_TOKEN` | env var **name** |
| `custom_body` | `""` | body for `template: custom`, `{{ENV_VAR}}` placeholders |
| `custom_message` | `""` | HTML line under the headline (verbatim) |
| `mentions` | `""` | e.g. `"@alice @bob"` |
| `max_lines` | `50` | trailing lines of failed output |
| `attach_log` | `false` | upload full failed-step output as a document |
| `buttons` | `true` | inline keyboard buttons (false → text links) |
| `include_links` | `true` | build / workflow / PR links |
| `include_duration` | `true` | `⏱ Duration` line |
| `thread_id` | `""` | forum topic |
| `silent` | `false` | no notification sound |
| `branch_pattern` / `tag_pattern` | `""` | comma-separated anchored regexes |
| `invert_match` | `false` | notify only when the ref does not match |
| `anthropic_api_key` | `ANTHROPIC_API_KEY` | env var **name** (`ai_summary`) |
| `ai_model` / `ai_max_tokens` | `claude-opus-5` / `700` | `ai_summary` request |
| `max_failed_tests` | `5` | failed tests listed by `test_summary` |
| `insights_window` / `workflow_name` | `last-30-days` / `""` | `insights` scope |
| `deploy_environment` | `""` | label for `deploy` |
| `dry_run` | `false` | print instead of send |
| `fail_on_error` | `false` | fail step on delivery error |
| `vcs_type` | `github` | or `bitbucket` |
| `api_base` | `https://api.telegram.org` | proxy / test double |
| `step_name` | `Telegram notification` | UI step name |

## 5. Templates

| Template | What it adds | Requires |
| --- | --- | --- |
| `test_summary` | counts, runtime, first failed tests | `store_test_results` before the step, `CIRCLE_TOKEN` |
| `insights` | success rate, p95, MTTR, throughput, flaky tests | `CIRCLE_TOKEN` |
| `ai_summary` | Claude summary, fix, copy-paste prompt (failures only) | `ANTHROPIC_API_KEY` |
| `deploy` | release card with linked tag | tag build |
| `custom` | your `custom_body` | — |

## 6. Verify with dry run

Add `dry_run: true` and push: the step output shows the exact HTML message.
Remove the flag once it looks right.
