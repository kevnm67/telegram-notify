#!/usr/bin/env python3
"""Generate src/commands/{notify,notify_failure,notify_success}.yml from one manifest.

Run after editing PARAMS / ENV_MAP so the three command files never drift.
"""

import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "src" / "commands"

PARAMS = [
    (
        "chat_id",
        "string",
        '""',
        'Telegram chat ID (user, group or channel, e.g. "-1001234567890"). Falls back to the TELEGRAM_CHAT_ID environment variable when empty so the ID can live in a context instead of the config.',
    ),
    (
        "bot_token",
        "env_var_name",
        "TELEGRAM_BOT_TOKEN",
        "Name of the environment variable holding the Telegram bot token.",
    ),
    (
        "circle_token",
        "env_var_name",
        "CIRCLE_TOKEN",
        "Name of the environment variable holding a CircleCI API token. Optional, but enables error output, job duration, test_summary and insights.",
    ),
    (
        "template",
        "enum:basic,test_summary,insights,ai_summary,deploy,custom",
        "basic",
        "Message layout. basic: status + metadata (+ error output on failure). test_summary: adds pass/fail/skip counts and failed test names from store_test_results. insights: adds workflow success rate, p95 duration, MTTR and flaky-test count. ai_summary: on failure, adds a Claude-generated summary, likely fix and a copy-paste prompt (needs anthropic_api_key). deploy: release card for tagged builds. custom: render custom_body with {{VAR}} substitution.",
    ),
    (
        "custom_body",
        "string",
        '""',
        'Body used by template: custom. Telegram HTML plus {{ENV_VAR}} placeholders (values are HTML-escaped), e.g. "<b>{{CIRCLE_JOB}}</b> finished on {{CIRCLE_BRANCH}}".',
    ),
    (
        "custom_message",
        "string",
        '""',
        "Extra line inserted under the headline. Telegram HTML is allowed and sent verbatim — only use trusted values.",
    ),
    (
        "mentions",
        "string",
        '""',
        'Space-separated Telegram usernames appended to the message (e.g. "@alice @bob").',
    ),
    (
        "max_lines",
        "integer",
        "50",
        "Trailing lines of the failed step's output to include.",
    ),
    (
        "attach_log",
        "boolean",
        "false",
        "On failure, also upload the failed step's full output as a .log document (reply to the message).",
    ),
    (
        "buttons",
        "boolean",
        "true",
        "Render View build / Workflow / Pull request as inline keyboard buttons. When false, the links are appended as text instead.",
    ),
    (
        "include_links",
        "boolean",
        "true",
        "Include build/workflow/PR links (as buttons or text).",
    ),
    (
        "include_duration",
        "boolean",
        "true",
        "Show the job duration (requires circle_token).",
    ),
    (
        "thread_id",
        "string",
        '""',
        "Forum topic (message_thread_id) to post into for group chats with topics enabled.",
    ),
    (
        "silent",
        "boolean",
        "false",
        "Send without a notification sound (Telegram disable_notification).",
    ),
    (
        "branch_pattern",
        "string",
        '""',
        'Comma-separated anchored regexes; only notify when the branch matches one (e.g. "main,release/.*"). Ignored on tag builds.',
    ),
    (
        "tag_pattern",
        "string",
        '""',
        'Comma-separated anchored regexes; only notify when the tag matches one (e.g. "v[0-9]+\\\\.[0-9]+\\\\.[0-9]+").',
    ),
    (
        "invert_match",
        "boolean",
        "false",
        "Invert branch_pattern / tag_pattern: notify only when the ref does NOT match.",
    ),
    (
        "anthropic_api_key",
        "env_var_name",
        "ANTHROPIC_API_KEY",
        "Name of the environment variable holding an Anthropic API key (template: ai_summary).",
    ),
    (
        "ai_model",
        "string",
        "claude-opus-5",
        "Claude model used by template: ai_summary.",
    ),
    (
        "ai_max_tokens",
        "integer",
        "700",
        "Maximum output tokens for the ai_summary request.",
    ),
    (
        "max_failed_tests",
        "integer",
        "5",
        "How many failed tests to list in template: test_summary.",
    ),
    (
        "insights_window",
        "enum:last-24-hours,last-7-days,last-30-days,last-60-days,last-90-days",
        "last-30-days",
        "Reporting window for template: insights.",
    ),
    (
        "workflow_name",
        "string",
        '""',
        "Workflow name for template: insights. Resolved from CIRCLE_WORKFLOW_ID via the API when empty.",
    ),
    (
        "deploy_environment",
        "string",
        '""',
        'Environment label shown by template: deploy (e.g. "production").',
    ),
    (
        "dry_run",
        "boolean",
        "false",
        "Print the rendered message (and buttons) to the step output instead of calling Telegram.",
    ),
    (
        "fail_on_error",
        "boolean",
        "false",
        "Fail the step if the notification cannot be sent. Off by default so the orb never masks the original job result.",
    ),
    (
        "vcs_type",
        "enum:github,bitbucket",
        "github",
        "VCS provider used for CircleCI API paths and commit/branch links.",
    ),
    (
        "api_base",
        "string",
        "https://api.telegram.org",
        "Telegram Bot API base URL. Override to point at a proxy or a test double.",
    ),
    (
        "step_name",
        "string",
        "Telegram notification",
        "Display name of the step in the CircleCI UI.",
    ),
]
ENV_MAP = {
    "chat_id": "CHAT_ID",
    "bot_token": "BOT_TOKEN_VAR",
    "circle_token": "CIRCLE_TOKEN_VAR",
    "template": "TEMPLATE",
    "custom_body": "CUSTOM_BODY",
    "custom_message": "CUSTOM_MESSAGE",
    "mentions": "MENTIONS",
    "max_lines": "MAX_LINES",
    "attach_log": "ATTACH_LOG",
    "buttons": "BUTTONS",
    "include_links": "INCLUDE_LINKS",
    "include_duration": "INCLUDE_DURATION",
    "thread_id": "THREAD_ID",
    "silent": "SILENT",
    "branch_pattern": "BRANCH_PATTERN",
    "tag_pattern": "TAG_PATTERN",
    "invert_match": "INVERT_MATCH",
    "anthropic_api_key": "ANTHROPIC_KEY_VAR",
    "ai_model": "AI_MODEL",
    "ai_max_tokens": "AI_MAX_TOKENS",
    "max_failed_tests": "MAX_FAILED_TESTS",
    "insights_window": "INSIGHTS_WINDOW",
    "workflow_name": "WORKFLOW_NAME",
    "deploy_environment": "DEPLOY_ENVIRONMENT",
    "dry_run": "DRY_RUN",
    "fail_on_error": "FAIL_ON_ERROR",
    "vcs_type": "VCS_TYPE",
    "api_base": "API_BASE",
}


def yaml_str(value):
    if value == '""':
        return '""'
    if any(c in value for c in ":#{}[]\"'") or value.startswith(
        ("<", ">", "&", "*", "!", "|", "%", "@", "`")
    ):
        return '"' + value.replace('"', '\\"') + '"'
    return value


def param_block(name, ptype, default, desc):
    out = f"  {name}:\n"
    if ptype.startswith("enum:"):
        out += "    type: enum\n    enum: [" + ", ".join(ptype[5:].split(",")) + "]\n"
    else:
        out += f"    type: {ptype}\n"
    out += f"    default: {yaml_str(default)}\n"
    wrapped = textwrap.wrap(
        desc, 100, initial_indent="      ", subsequent_indent="      "
    )
    out += "    description: >\n" + "\n".join(wrapped) + "\n"
    return out


def env_block(indent, event):
    lines = [f"{indent}TELEGRAM_NOTIFY_EVENT: {event}"]
    for name, *_ in PARAMS:
        if name in ENV_MAP:
            lines.append(
                f"{indent}TELEGRAM_NOTIFY_{ENV_MAP[name]}: << parameters.{name} >>"
            )
    return "\n".join(lines)


def run_step(indent, when, event):
    i = indent
    return (
        f"{i}- run:\n{i}    name: << parameters.step_name >>\n{i}    when: {when}\n{i}    environment:\n"
        + env_block(i + "      ", event)
        + f"\n{i}    command: << include(scripts/notify.sh) >>\n"
    )


def write_notify():
    s = (
        "description: >\n  Send a Telegram message about the current job. Choose when it fires with\n"
        "  `event`: `failure` (default, runs `when: on_fail`), `success` (`when:\n"
        "  on_success`) or `always` (runs at the end of every job and reports the\n"
        "  job's real outcome). Pick a layout with `template` (basic, test_summary,\n"
        "  insights, ai_summary, deploy, custom). Failure messages include the failed\n"
        "  step's output fetched from the CircleCI API when `circle_token` is available.\n\nparameters:\n"
    )
    s += "  event:\n    type: enum\n    enum: [failure, success, always]\n    default: failure\n    description: When to send the notification.\n"
    for p in PARAMS:
        s += param_block(*p)
    s += "\nsteps:\n"
    s += (
        "  - when:\n      condition:\n        equal: [always, << parameters.event >>]\n      steps:\n"
        '        - run:\n            name: "<< parameters.step_name >> (record outcome)"\n'
        "            when: on_fail\n            command: << include(scripts/record_failure.sh) >>\n"
    )
    s += run_step("        ", "always", "always")
    s += (
        "  - when:\n      condition:\n        equal: [failure, << parameters.event >>]\n      steps:\n"
        + run_step("        ", "on_fail", "failure")
    )
    s += (
        "  - when:\n      condition:\n        equal: [success, << parameters.event >>]\n      steps:\n"
        + run_step("        ", "on_success", "success")
    )
    (ROOT / "notify.yml").write_text(s)


def write_wrapper(event, desc):
    s = f"description: >\n  {desc}\n\nparameters:\n"
    for p in PARAMS:
        s += param_block(*p)
    s += f"\nsteps:\n  - notify:\n      event: {event}\n"
    for name, *_ in PARAMS:
        s += f"      {name}: << parameters.{name} >>\n"
    (ROOT / f"notify_{event}.yml").write_text(s)


if __name__ == "__main__":
    write_notify()
    write_wrapper(
        "failure",
        "Send a Telegram message when the job fails (runs `when: on_fail`). Includes the\n  failed step's output when `circle_token` is available. Shorthand for `notify`\n  with `event: failure`; accepts the same parameters.",
    )
    write_wrapper(
        "success",
        "Send a Telegram message when the job succeeds (runs `when: on_success`).\n  Shorthand for `notify` with `event: success`; accepts the same parameters.",
    )
    print("generated", sorted(p.name for p in ROOT.glob("*.yml")))
