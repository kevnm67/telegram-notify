# Architecture

## Contents

- [Flow](#flow)
- [Components](#components)
- [Event handling](#event-handling)
- [Error output retrieval](#error-output-retrieval)
- [Message building and safety](#message-building-and-safety)
- [Delivery](#delivery)

## Flow

![Notification flow](notification_flow.svg)

## Components

| Component | Role |
| ----------- | ------ |
| `commands/notify.yml` | Maps parameters to `TELEGRAM_NOTIFY_*` env vars; picks `when:` from `event` |
| `commands/notify_failure.yml`, `notify_success.yml` | Wrappers calling `notify` |
| `scripts/record_failure.sh` | `when: on_fail` step that drops a marker file (`$TMPDIR/telegram_notify_job_failed`) |
| `scripts/notify.sh` | Resolves status → fetches error output → builds HTML → POSTs to Telegram |

## Event handling

| `event` | Steps emitted |
| --------- | --------------- |
| `failure` | one `run` with `when: on_fail` |
| `success` | one `run` with `when: on_success` |
| `always` | `record_failure.sh` (`on_fail`) then `notify.sh` (`always`), which reads the marker |

## Error output retrieval

Only on failure and only when the `circle_token` variable is set:

1. `GET {api}/project/{vcs_type}/{org}/{repo}/{CIRCLE_BUILD_NUM}` (v1.1).
2. Select the action with `failed == true` / `status == failed|timedout`
   (`jq`; grep fallback picks the last `output_url`).
3. Download `output_url`, join `message` fields (`jq` → `python3` → sed
   fallback), strip ANSI, keep the last `max_lines`.

Any failure in this chain logs a line and sends the message without the
error block.

## Message building and safety

- Repository, branch (or tag), job, commit, actor are HTML-escaped.
- Error block truncated to 3 000 chars **before** escaping, wrapped in
  `<pre>`; the final message is capped at 4 096 chars.
- `custom_message` and `mentions` are inserted verbatim (trusted config).

## Delivery

`curl --data-urlencode` form POST to `{api_base}/bot{token}/sendMessage`
with `parse_mode=HTML`, `disable_web_page_preview=true`, optional
`disable_notification` and `message_thread_id`. Success requires HTTP 200
and `"ok":true`; otherwise the response (not the token) is logged and the
step exits 0 unless `fail_on_error`.
