# telegram-notify

CircleCI orb for rich Telegram notifications — failure (with error output),
success, or always — with templates for test summaries, CI insights, AI
failure analysis and releases.

## Contents

- [Installation](Installation) — bot setup, context, first config
- [Development](Development) — local tooling, tests, coverage, releases
- [Architecture](Architecture) — how a notification flows end to end

## Quick links

- Orb registry: <https://circleci.com/developer/orbs/orb/kevnm67/telegram-notify>
- Source: <https://github.com/kevnm67/telegram-notify>
- CI: <https://app.circleci.com/pipelines/github/kevnm67/telegram-notify>
- Quality & coverage: <https://qlty.sh/gh/kevnm67/projects/telegram-notify>

## At a glance

```yaml
orbs:
  telegram-notify: kevnm67/telegram-notify@0.0.1

steps:
  - telegram-notify/notify_failure:
      chat_id: "-1001234567890"
      template: ai_summary
      attach_log: true
```
