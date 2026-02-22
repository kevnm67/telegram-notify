# AGENTS.md - CircleCI Failure Notifier Orb

## What This Is

A CircleCI orb that sends Telegram notifications when CI builds fail, complete with error context and build details.

## Key Components

### Orb Structure
- **`src/@orb.yml`** - Orb metadata and configuration
- **`src/commands/notify-failure.yml`** - Main command definition
- **`src/scripts/notify-failure.sh`** - Core notification logic in bash

### Key Features
- Runs `when: on_fail` - only executes when jobs fail
- Fetches actual error output via CircleCI v1.1 API
- Formats rich HTML messages for Telegram
- Failure-safe - never causes additional build failures
- Pure bash - no dependencies, works on any executor

### Required Context Variables
Users need a CircleCI context with:
- `TELEGRAM_BOT_TOKEN` - Telegram bot token
- `CIRCLE_TOKEN` - CircleCI API token for error detail fetching

## Common Tasks

### Testing Changes
```bash
# Validate orb locally
circleci orb validate src/@orb.yml

# Pack for testing
circleci orb pack src/ > orb.yml

# Publish dev version
circleci orb publish orb.yml kevnm67/ci-failure-notifier@dev:first
```

### Debugging Notifications
The script logs all actions with `[ci-failure-notifier]` prefix. Common issues:
- Missing `TELEGRAM_BOT_TOKEN` or `CIRCLE_TOKEN`
- Invalid chat ID format (should be string)
- API rate limits or network issues
- Messages exceeding Telegram's 4096 char limit

### Message Format
```
🔴 CI Failure
📁 Repository: repo-name
🌿 Branch: branch-name  
⚙️ Job: job-name
📝 Commit: sha-short
❌ Error Output: [last N lines of failed step]
🔗 View Build | View Workflow
```

## Architecture Notes

### Error Collection Flow
1. Check if `CIRCLE_TOKEN` is available
2. Call CircleCI v1.1 API: `/project/github/{org}/{repo}/{build_num}`
3. Parse JSON response to find failed step output URLs
4. Fetch actual error output from step URLs
5. Truncate to fit Telegram limits
6. Send formatted HTML message

### Failure Safety
- Uses `set +e` - never fail on errors
- All API calls have fallbacks
- Messages auto-truncate to 4000 chars (with buffer)
- Always exits 0 to preserve original build failure

### CircleCI Integration
- Uses built-in env vars: `CIRCLE_*`
- Works with `when: on_fail` condition
- Can be used in steps or post-steps
- Supports all executor types (Docker, macOS, machine)

## Development Workflow

1. **Local testing**: Use CircleCI CLI for validation
2. **Dev publishing**: Push branches trigger dev orb versions
3. **Integration testing**: Test in real CI environments
4. **Production release**: Merging to main publishes production version

## Troubleshooting

### No notifications
- Check context is attached to job
- Verify bot token and chat ID
- Test bot manually: `curl -X POST https://api.telegram.org/bot<TOKEN>/sendMessage -d '{"chat_id":"<ID>","text":"test"}'`

### Missing error details  
- Verify `CIRCLE_TOKEN` has project access
- Check if build actually failed (not cancelled)
- Some executors may not have accessible logs

### Message truncation
- Reduce `max_lines` parameter
- Error output truncated at 4000 chars automatically
- Consider splitting long errors across multiple notifications

## Files Overview

- **CircleCI Orb**: `src/` directory with standard orb structure
- **CI Pipeline**: `.circleci/config.yml` for orb development
- **Documentation**: `README.md`, `ARCHITECTURE.md`  
- **Config**: `.markdownlint.yaml`, `.pre-commit-config.yaml`
- **License**: MIT license