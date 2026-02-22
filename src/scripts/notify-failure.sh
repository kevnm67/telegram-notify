#!/bin/bash

# CI Failure Notification Script
# Never fail the build - handle all errors gracefully
set +e

# Function to log messages
log() {
    echo "[ci-failure-notifier] $1"
}

# Function to safely truncate text to fit Telegram's 4096 char limit
truncate_message() {
    local message="$1"
    local max_length=4000  # Leave some buffer for safety
    
    if [ ${#message} -gt $max_length ]; then
        echo "${message:0:$max_length}..."
    else
        echo "$message"
    fi
}

# Function to send Telegram message
send_telegram_message() {
    local message="$1"
    local truncated_message
    
    truncated_message=$(truncate_message "$message")
    
    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        log "ERROR: TELEGRAM_BOT_TOKEN not set. Cannot send notification."
        return 1
    fi
    
    if [ -z "$NOTIFY_CHAT_ID" ]; then
        log "ERROR: chat_id not provided. Cannot send notification."
        return 1
    fi
    
    local response
    response=$(curl -s -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"$NOTIFY_CHAT_ID\",
            \"text\": \"$truncated_message\",
            \"parse_mode\": \"HTML\",
            \"disable_web_page_preview\": true
        }")
    
    if [ $? -eq 0 ]; then
        log "Telegram notification sent successfully"
        return 0
    else
        log "ERROR: Failed to send Telegram notification"
        log "Response: $response"
        return 1
    fi
}

# Function to get error details from CircleCI API
get_error_details() {
    if [ -z "$CIRCLE_TOKEN" ]; then
        log "CIRCLE_TOKEN not set. Skipping error detail fetch."
        echo "Error details unavailable (CIRCLE_TOKEN not configured)"
        return 0
    fi
    
    local org_repo="${CIRCLE_PROJECT_USERNAME:-unknown}/${CIRCLE_PROJECT_REPONAME:-unknown}"
    local build_num="${CIRCLE_BUILD_NUM:-unknown}"
    
    if [ "$build_num" = "unknown" ]; then
        log "Build number not available. Skipping error detail fetch."
        echo "Error details unavailable (no build number)"
        return 0
    fi
    
    local api_url="https://circleci.com/api/v1.1/project/github/$org_repo/$build_num"
    local build_data
    
    log "Fetching build details from: $api_url"
    
    build_data=$(curl -s -H "Circle-Token: $CIRCLE_TOKEN" "$api_url")
    
    if [ $? -ne 0 ] || [ -z "$build_data" ]; then
        log "Failed to fetch build data from CircleCI API"
        echo "Error details unavailable (API fetch failed)"
        return 0
    fi
    
    # Parse JSON to find failed steps (basic parsing without jq dependency)
    # Look for failed steps and extract their output URLs
    local error_output=""
    local step_output_url=""
    
    # Extract step output URLs using grep and sed
    step_output_url=$(echo "$build_data" | grep -o '"output_url":"[^"]*"' | grep -o 'https://[^"]*' | head -1)
    
    if [ -n "$step_output_url" ]; then
        log "Found step output URL: $step_output_url"
        
        # Fetch the actual error output
        local step_output
        step_output=$(curl -s "$step_output_url")
        
        if [ $? -eq 0 ] && [ -n "$step_output" ]; then
            # Get last N lines of output
            local max_lines=${NOTIFY_MAX_LINES:-50}
            error_output=$(echo "$step_output" | tail -n "$max_lines" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            
            if [ -n "$error_output" ]; then
                echo "$error_output"
                return 0
            fi
        fi
    fi
    
    # Fallback: try to extract error info from build data directly
    log "No step output URL found, using build data directly"
    echo "Error details unavailable (could not extract from API response)"
}

# Main execution
main() {
    log "Starting CI failure notification"
    
    # Collect build information
    local repo_name="${CIRCLE_PROJECT_REPONAME:-unknown}"
    local branch="${CIRCLE_BRANCH:-unknown}"
    local job_name="${CIRCLE_JOB:-unknown}"
    local build_num="${CIRCLE_BUILD_NUM:-unknown}"
    local build_url="${CIRCLE_BUILD_URL:-unknown}"
    local workflow_id="${CIRCLE_WORKFLOW_ID:-unknown}"
    local commit_sha="${CIRCLE_SHA1:-unknown}"
    local commit_short="${commit_sha:0:8}"
    
    # Get error details
    local error_details
    error_details=$(get_error_details)
    
    # Build the Telegram message
    local message
    message="🔴 <b>CI Failure</b>

📁 <b>Repository:</b> $repo_name
🌿 <b>Branch:</b> $branch
⚙️ <b>Job:</b> $job_name
📝 <b>Commit:</b> $commit_short"
    
    if [ -n "$error_details" ] && [ "$error_details" != "Error details unavailable"* ]; then
        message="$message

❌ <b>Error Output:</b>
<pre>$error_details</pre>"
    fi
    
    # Add links if available
    if [ "$NOTIFY_INCLUDE_LOG_LINK" = "true" ] && [ "$build_url" != "unknown" ]; then
        message="$message

🔗 <a href=\"$build_url\">View Build</a>"
        
        if [ "$workflow_id" != "unknown" ]; then
            local workflow_url="https://app.circleci.com/pipelines/workflows/$workflow_id"
            message="$message | <a href=\"$workflow_url\">View Workflow</a>"
        fi
    fi
    
    # Send the notification
    send_telegram_message "$message"
    
    log "CI failure notification process completed"
    
    # Always exit 0 to not interfere with the original build failure
    exit 0
}

# Execute main function
main "$@"