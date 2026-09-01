# Architecture

## Contents

- [Flow](#flow)
- [Components](#components)
- [Event handling](#event-handling)
- [Error output retrieval](#error-output-retrieval)
- [Message building and safety](#message-building-and-safety)
- [Delivery](#delivery)

## Flow

<a href="notification_flow-dark.svg" target="_blank">
  <img src="notification_flow-dark.svg"
       alt="A CircleCI job invokes the orb command; notify.sh filters on branch or tag,
            resolves job status, reads failed-step output, tests and insights from the
            CircleCI API plus an optional Anthropic summary, then posts an HTML message
            with inline buttons to the Telegram Bot API"
       width="100%">
</a>

*Click the diagram to open it full size. It is vector, so it stays sharp at any zoom.*

Source is `docs/architecture/notification_flow.d2` in the main repo — regenerate with
`make diagrams`:

```bash
d2 --bundle --theme 200 --layout elk --pad 60 \
   docs/architecture/notification_flow.d2 docs/architecture/notification_flow-dark.svg
```

## Components

| Component | Role |
| ----------- | ------ |
| `commands/notify.yml` | Maps parameters to `TELEGRAM_NOTIFY_*` env vars; picks `when:` from `event` |
| `commands/notify_failure.yml`, `notify_success.yml` | Wrappers calling `notify` |
| `scripts/record_failure.sh` | `when: on_fail` step that drops a marker file (`$TMPDIR/telegram_notify_job_failed`) |
| `scripts/notify.sh` | Filters → status → CircleCI/Anthropic fetches → template section → HTML → `sendMessage` (+ `sendDocument`) |
| `scripts/dev/generate-commands.py` | Parameter manifest that generates the three command files |

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

## Templates

| Template | Data source | Function |
| --- | --- | --- |
| `test_summary` | `GET /api/v2/project/{slug}/{job}/tests` | `tn_section_test_summary` |
| `insights` | `GET /api/v2/workflow/{id}` (name) → `/insights/{slug}/workflows/{name}/summary` + `/flaky-tests` | `tn_section_insights` |
| `ai_summary` | `POST https://api.anthropic.com/v1/messages` with the error tail; response parsed into SUMMARY / FIX / PROMPT | `tn_section_ai_summary` |
| `deploy` | `CIRCLE_TAG` + `deploy_environment` | `tn_section_deploy` |
| `custom` | `custom_body` with `{{VAR}}` → escaped env values | `tn_render_custom` |

Sections are appended after the metadata block and before the error output;
the error block budget shrinks so the whole message stays under 4 096 chars.

## Message building and safety

- Repository, branch (or tag), job and PR are rendered as links (`tn_link`
  escapes both label and href); commit, actor, test names, log lines and AI
  output are HTML-escaped.
- `branch_pattern` / `tag_pattern` are evaluated first (`tn_should_send`);
  a non-match logs `Skipped:` and exits 0.
- Error block truncated to 3 000 chars **before** escaping, wrapped in
  `<pre>`; the final message is capped at 4 096 chars.
- `custom_message` and `mentions` are inserted verbatim (trusted config).

## Delivery

`curl --data-urlencode` form POST to `{api_base}/bot{token}/sendMessage`
with `parse_mode=HTML`, `disable_web_page_preview=true`, an inline keyboard in
`reply_markup` (`buttons`), optional `disable_notification` and
`message_thread_id`. With `attach_log`, a second multipart `sendDocument`
replies to the message with the full failed-step log. Success requires HTTP 200
and `"ok":true`; otherwise the response (not the token) is logged and the
step exits 0 unless `fail_on_error`.
