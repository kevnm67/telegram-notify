# CircleCI Failure Notifier Orb

A CircleCI orb that sends instant Telegram notifications when your CI builds fail, complete with error analysis and context.

## Features

- 🔴 **Instant notifications** when CI jobs fail
- 📋 **Rich context** including repo, branch, job, and commit info
- 🐛 **Error analysis** with actual failure output from CircleCI API
- 📱 **Telegram integration** with HTML formatting
- 🛡️ **Failure-safe** - never causes additional build failures
- ⚡ **Zero dependencies** - pure bash, works on any CircleCI executor

## Quick Start

### 1. Set Up Telegram Bot

1. Create a Telegram bot via [@BotFather](https://t.me/botfather)
2. Get your bot token (looks like `123456789:ABCdefGHIjklMNOpqrSTUvwxYZ`)
3. Get your chat ID:
   - Message your bot
   - Visit `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - Find your chat ID in the response

### 2. Configure CircleCI Context

Create a CircleCI context (e.g., `ci-notify`) with these environment variables:

- `TELEGRAM_BOT_TOKEN` - Your Telegram bot token
- `CIRCLE_TOKEN` - CircleCI API token (for error detail fetching)

### 3. Add to Your Project

```yaml
version: 2.1

orbs:
  ci-notify: kevnm67/ci-failure-notifier@0.1.0

jobs:
  build:
    steps:
      - checkout
      - run: make build
      - ci-notify/notify-failure:
          chat_id: "YOUR_CHAT_ID"
```

### 4. Alternative: Post-Steps

```yaml
version: 2.1

orbs:
  ci-notify: kevnm67/ci-failure-notifier@0.1.0

workflows:
  build_and_test:
    jobs:
      - build:
          post-steps:
            - ci-notify/notify-failure:
                chat_id: "YOUR_CHAT_ID"
          context:
            - ci-notify
```

## Command Reference

### `notify-failure`

Sends a Telegram notification when a job fails.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `chat_id` | string | Yes | - | Telegram chat ID to notify |
| `max_lines` | integer | No | 50 | Max lines of error output to include |
| `include_log_link` | boolean | No | true | Include links to build and workflow |

#### Example

```yaml
- ci-notify/notify-failure:
    chat_id: "8233849210"
    max_lines: 30
    include_log_link: false
```

## Message Format

The orb sends rich HTML-formatted messages:

```
🔴 CI Failure

📁 Repository: my-project
🌿 Branch: feature/new-feature
⚙️ Job: build
📝 Commit: a1b2c3d4

❌ Error Output:
make: *** [build] Error 1
npm ERR! Build failed with exit code 1
npm ERR! Failed at build step

🔗 View Build | View Workflow
```

## Environment Variables

The orb automatically uses these CircleCI built-in environment variables:

- `CIRCLE_PROJECT_REPONAME` - Repository name
- `CIRCLE_BRANCH` - Branch name
- `CIRCLE_JOB` - Job name
- `CIRCLE_BUILD_NUM` - Build number
- `CIRCLE_BUILD_URL` - Build URL
- `CIRCLE_WORKFLOW_ID` - Workflow ID
- `CIRCLE_SHA1` - Commit SHA
- `CIRCLE_PROJECT_USERNAME` - GitHub username/org

## Error Handling

The orb is designed to be failure-safe:

- **Missing tokens**: Skips API calls, sends basic notification
- **API failures**: Falls back to basic build info
- **Telegram errors**: Logs error but doesn't fail the build
- **Long messages**: Automatically truncated to fit Telegram limits (4096 chars)

## Requirements

- CircleCI 2.1+
- Bash (available on all CircleCI executors)
- Internet access for API calls

## Permissions

The CircleCI API token needs:

- Read access to your projects
- Build artifact access (for error output)

## Troubleshooting

### No notifications received

1. Verify `TELEGRAM_BOT_TOKEN` is correct
2. Check chat ID is correct (should be a string)
3. Ensure the bot can message your chat
4. Check CircleCI context is attached to the job

### Missing error details

1. Verify `CIRCLE_TOKEN` is set and has proper permissions
2. Check the build actually failed (notifications only send on failure)
3. Some job types may not have accessible output logs

### Message too long

Reduce `max_lines` parameter:

```yaml
- ci-notify/notify-failure:
    chat_id: "YOUR_CHAT_ID"
    max_lines: 20
```

## Examples

### Basic setup

```yaml
version: 2.1

orbs:
  ci-notify: kevnm67/ci-failure-notifier@0.1.0

jobs:
  test:
    docker:
      - image: circleci/node:16
    steps:
      - checkout
      - run: npm test
      - ci-notify/notify-failure:
          chat_id: "8233849210"

workflows:
  test_and_deploy:
    jobs:
      - test:
          context:
            - ci-notify
```

### Multiple notifications

```yaml
version: 2.1

orbs:
  ci-notify: kevnm67/ci-failure-notifier@0.1.0

jobs:
  build:
    steps:
      - checkout
      - run: make build
      - ci-notify/notify-failure:
          chat_id: "8233849210"  # Team chat
      - ci-notify/notify-failure:
          chat_id: "-1001234567890"  # Alert channel
```

### Custom error output

```yaml
- ci-notify/notify-failure:
    chat_id: "8233849210"
    max_lines: 100
    include_log_link: true
```

## Development

See [ARCHITECTURE.md](ARCHITECTURE.md) for technical details.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

Issues and feature requests are welcome!