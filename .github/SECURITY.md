# Security Policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Email
<kevin.morton@mac.com> with a description, reproduction steps and the orb
version affected. You will get an acknowledgement within 72 hours and a fix
or mitigation plan within 14 days for confirmed issues.

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | ✅ |
| 0.x | ❌ (pre-release, upgrade to 1.x) |

## Security considerations for this orb

- **Secrets never leave your CircleCI context.** The bot token and CircleCI
  API token are read from environment variables (`TELEGRAM_BOT_TOKEN`,
  `CIRCLE_TOKEN` by default). They are never written to step output; the
  token only appears in the Telegram request URL, which `curl -sS` does not
  echo.
- **Output is HTML-escaped.** Repository, branch, job, commit and fetched
  error output are escaped before being placed in the message so job output
  cannot inject Telegram markup. `custom_message` and `mentions` are sent
  verbatim by design — treat them as trusted configuration.
- **Error output may contain sensitive data.** The failed step's last
  `max_lines` lines are posted to the chat. Mask secrets in your CI logs or
  set `max_lines: 0`/omit `CIRCLE_TOKEN` if logs may contain credentials.
- **Least-privilege tokens.** `CIRCLE_TOKEN` only needs read access to the
  project; use a project-scoped token where possible.
- **Pinned dependencies.** Orbs, Docker images, GitHub Actions (by SHA) and
  pre-commit hooks are pinned and updated by Renovate.
