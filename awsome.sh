#!/bin/bash

# AWS Session Manager (AWsome)
# https://github.com/dlutsch/awsome
#
# MIT License
# Copyright (c) 2025 dlutsch
# See LICENSE file for full license text

# Config file location
AWSOME_CONFIG_DIR="$HOME/.config/awsome"
AWSOME_CONFIG_FILE="$AWSOME_CONFIG_DIR/config"

# Variables that will be populated from config file
DEFAULT_REGION=""
SSO_REGION=""
SSO_START_URL=""

# Repository directory (where git commands will be executed)
REPO_DIR="${REPO_DIR:-$HOME/.local/share/awsome}"

# Update check cache file
UPDATE_CACHE_FILE="$AWSOME_CONFIG_DIR/update-cache.json"
# Default cache validity in seconds (24 hours)
UPDATE_CACHE_DURATION=86400
# Timeout for git network operations in seconds
GIT_TIMEOUT=2

# Function to read update cache
read_update_cache() {
    # Initialize default values
    LAST_CHECK=0
    LAST_SUCCESSFUL_CHECK=0
    FAILED_CHECKS=0
    REMOTE_HEAD=""
    BEHIND_COUNT=0
    CACHE_EXPIRES_AT=0
    
    if [ -f "$UPDATE_CACHE_FILE" ]; then
        # Read values from cache file if it exists
        # Using grep and cut for basic parsing since jq might not be available
        LAST_CHECK=$(grep -o '"last_check":[0-9]*' "$UPDATE_CACHE_FILE" 2>/dev/null | cut -d ':' -f 2 || echo "0")
        LAST_SUCCESSFUL_CHECK=$(grep -o '"last_successful_check":[0-9]*' "$UPDATE_CACHE_FILE" 2>/dev/null | cut -d ':' -f 2 || echo "0")
        FAILED_CHECKS=$(grep -o '"failed_checks":[0-9]*' "$UPDATE_CACHE_FILE" 2>/dev/null | cut -d ':' -f 2 || echo "0")
        REMOTE_HEAD=$(grep -o '"remote_head":"[^"]*"' "$UPDATE_CACHE_FILE" 2>/dev/null | cut -d '"' -f 4 || echo "")
        BEHIND_COUNT=$(grep -o '"behind_count":[0-9]*' "$UPDATE_CACHE_FILE" 2>/dev/null | cut -d ':' -f 2 || echo "0")
        CACHE_EXPIRES_AT=$(grep -o '"expires_at":[0-9]*' "$UPDATE_CACHE_FILE" 2>/dev/null | cut -d ':' -f 2 || echo "0")
    fi
}

# Function to write update cache
write_update_cache() {
    local current_time timestamp success_time behind remote_head
    
    current_time=$(date +%s)
    timestamp=$current_time
    success_time=$1
    behind=$2
    remote_head=$3
    
    # Ensure config directory exists
    mkdir -p "$AWSOME_CONFIG_DIR" 2>/dev/null
    
    # Calculate expiration time
    local expires_at=$((current_time + UPDATE_CACHE_DURATION))
    
    # Write cache file
    cat > "$UPDATE_CACHE_FILE" << EOL
{
  "last_check": $timestamp,
  "last_successful_check": $success_time,
  "failed_checks": $FAILED_CHECKS,
  "remote_head": "$remote_head",
  "behind_count": $behind,
  "expires_at": $expires_at
}
EOL
}

# Function to check for available updates with caching
check_for_updates() {
    # Only check if git is installed
    if ! command -v git &> /dev/null; then
        return 0
    fi
    
    # Check if repo directory exists and is a git repo
    if [ ! -d "$REPO_DIR" ] || [ ! -d "$REPO_DIR/.git" ]; then
        # Don't show errors during normal operation, but still return safely
        return 0
    fi
    
    # If we've already shown the update banner recently, don't show it again
    if update_banner_shown; then
        return 0
    fi
    
    # Current time
    local current_time
    current_time=$(date +%s)
    
    # Read the cache
    read_update_cache
    
    # Check if cache is still valid (not expired)
    if [ "$current_time" -lt "$CACHE_EXPIRES_AT" ]; then
        # Cache is still valid, use cached data
        if [ "$BEHIND_COUNT" -gt 0 ]; then
            # Mark that we've shown the banner
            mark_update_banner_shown
            
            echo ""
            gum style \
                --foreground 3 --background 0 --border double --border-foreground 3 \
                --align center --width 70 --margin "1 0" --padding "0 2" \
                "🚀 Update Available! There are $BEHIND_COUNT new changes available." \
                "Run 'awu' or select 'Update AWsome' from the menu to upgrade."
            echo ""
        fi
        
        # Show offline indicator if we've had multiple failed checks and last successful check was a while ago
        if [ "$FAILED_CHECKS" -gt 3 ] && [ "$((current_time - LAST_SUCCESSFUL_CHECK))" -gt "$((UPDATE_CACHE_DURATION * 3))" ]; then
            echo ""
            gum style \
                --foreground 8 --align right --width 70 \
                "⚠️ Update checks failing. Network issues?"
            echo ""
        fi
        
        return 0
    fi
    
    # Check quietly - we don't want to show errors if network is down
    (
        # Try to access the repo directory
        if ! cd "$REPO_DIR" 2>/dev/null; then
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            write_update_cache "$LAST_SUCCESSFUL_CHECK" "$BEHIND_COUNT" "$REMOTE_HEAD"
            return 0
        fi
        
        # Verify we can get the current HEAD (basic git operations work)
        local_head=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        if [ "$local_head" = "unknown" ]; then
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            write_update_cache "$LAST_SUCCESSFUL_CHECK" "$BEHIND_COUNT" "$REMOTE_HEAD"
            return 0
        fi
        
        # Check remote configuration
        remote_url=$(git remote get-url origin 2>/dev/null || echo "")
        if [ -z "$remote_url" ]; then
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            write_update_cache "$LAST_SUCCESSFUL_CHECK" "$BEHIND_COUNT" "$REMOTE_HEAD"
            return 0
        fi
        
        # Determine the remote branch name (main or master)
        remote_branch="main"
        
        # Try a fast remote check first
        if timeout $GIT_TIMEOUT git ls-remote --heads origin "$remote_branch" &>/dev/null; then
            # Got remote data successfully
            
            # Fetch quietly with a short timeout
            if ! timeout $GIT_TIMEOUT git fetch --quiet origin 2>/dev/null; then
                # Fetch failed, increment failed checks counter
                FAILED_CHECKS=$((FAILED_CHECKS + 1))
                write_update_cache "$LAST_SUCCESSFUL_CHECK" "$BEHIND_COUNT" "$REMOTE_HEAD"
                return 0
            fi
            
            # Try to get the remote head
            if ! git rev-parse origin/$remote_branch &>/dev/null; then
                # If main branch doesn't exist, try master
                if ! git rev-parse origin/master &>/dev/null; then
                    FAILED_CHECKS=$((FAILED_CHECKS + 1))
                    write_update_cache "$LAST_SUCCESSFUL_CHECK" "$BEHIND_COUNT" "$REMOTE_HEAD"
                    return 0
                else
                    remote_branch="master"
                fi
            fi
            
            # Get the latest remote HEAD
            new_remote_head=$(git rev-parse origin/$remote_branch 2>/dev/null || echo "unknown")
            if [ "$new_remote_head" = "unknown" ]; then
                FAILED_CHECKS=$((FAILED_CHECKS + 1))
                write_update_cache "$LAST_SUCCESSFUL_CHECK" "$BEHIND_COUNT" "$REMOTE_HEAD"
                return 0
            fi
            
            # Check if we're behind the remote
            new_behind_count=$(git rev-list HEAD..origin/$remote_branch --count 2>/dev/null || echo "0")
            
            # Update cache with success
            FAILED_CHECKS=0
            write_update_cache "$current_time" "$new_behind_count" "$new_remote_head"
            
            # If there are updates available, show banner
            if [ "$new_behind_count" -gt 0 ]; then
                # Mark that we've shown the banner
                mark_update_banner_shown
                
                echo ""
                gum style \
                    --foreground 3 --background 0 --border double --border-foreground 3 \
                    --align center --width 70 --margin "1 0" --padding "0 2" \
                    "🚀 Update Available! There are $new_behind_count new changes available." \
                    "Run 'awsm update' or select 'Update AWsome' from the menu to upgrade."
                echo ""
            fi
        else
            # Network failed, increment failed checks counter
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            
            # Use cached data if we have it
            write_update_cache "$LAST_SUCCESSFUL_CHECK" "$BEHIND_COUNT" "$REMOTE_HEAD"
            
            # Only show cached update banner if cached data indicates updates
            if [ "$BEHIND_COUNT" -gt 0 ]; then
                # Mark that we've shown the banner
                mark_update_banner_shown
                
                echo ""
                gum style \
                    --foreground 3 --background 0 --border double --border-foreground 3 \
                    --align center --width 70 --margin "1 0" --padding "0 2" \
                    "🚀 Update Available! There are $BEHIND_COUNT new changes available." \
                    "Run 'awsm update' or select 'Update AWsome' from the menu to upgrade."
                echo ""
            fi
            
            # If we've had multiple failed checks, show a small indicator
            if [ "$FAILED_CHECKS" -gt 3 ]; then
                echo ""
                gum style \
                    --foreground 8 --align right --width 70 \
                    "⚠️ Update checks failing. Network issues?"
                echo ""
            fi
        fi
    ) 2>/dev/null # Suppress all errors from the subshell
}

# Check for config file and create it if it doesn't exist
ensure_config_exists() {
    # Create config directory if it doesn't exist
    if [ ! -d "$AWSOME_CONFIG_DIR" ]; then
        mkdir -p "$AWSOME_CONFIG_DIR"
    fi
    
    # Create config file with defaults if it doesn't exist
    if [ ! -f "$AWSOME_CONFIG_FILE" ]; then
        cat > "$AWSOME_CONFIG_FILE" <<EOL
# AWsome Configuration
# Generated on $(date)

# AWS Default Region (used for standard AWS CLI operations)
DEFAULT_AWS_REGION="us-west-2"

# AWS SSO Region (used for SSO login)
SSO_AWS_REGION="us-west-2"

# AWS SSO Start URL (REQUIRED)
SSO_START_URL="$SSO_START_URL"
EOL
        echo "Created default configuration file at $AWSOME_CONFIG_FILE"
        echo "Please edit this file to set your SSO Start URL before using AWsome."
        
        # If SSO_START_URL is empty, advise the user to configure it
        if [ -z "$SSO_START_URL" ]; then
            echo "ERROR: SSO Start URL is required. Please run:"
            echo "  awsm config"
            echo "Or edit the config file directly to set your SSO Start URL."
        fi
    fi

    # Read from the config file
    source "$AWSOME_CONFIG_FILE"

    # Update variables with values from the config file
    if [ -n "$DEFAULT_AWS_REGION" ]; then
        DEFAULT_REGION="$DEFAULT_AWS_REGION"
    fi
    if [ -n "$SSO_AWS_REGION" ]; then
        SSO_REGION="$SSO_AWS_REGION"
    fi

    # Fall back to a single region if either is missing
    if [ -n "$AWS_REGION" ]; then
        # For backwards compatibility
        if [ -z "$DEFAULT_REGION" ]; then
            DEFAULT_REGION="$AWS_REGION"
        fi
        if [ -z "$SSO_REGION" ]; then
            SSO_REGION="$AWS_REGION"
        fi
    fi
        
    # Ensure SSO_START_URL is set
    if [ -z "$SSO_START_URL" ]; then
        echo "ERROR: SSO Start URL is not set in $AWSOME_CONFIG_FILE"
        echo "Please edit the config file to set your SSO Start URL before using AWsome."
        return 1
    fi
}

# Ensure config exists before proceeding
ensure_config_exists || {
    # If we're just showing config, don't exit
    if [[ "$1" != "config" && "$1" != "c" ]]; then
        exit 1
    fi
}

precheck() {
    # Create AWS config directory if it doesn't exist
    mkdir -p "$HOME/.aws"
    
    # Path to AWS config file
    AWS_CONFIG_FILE="$HOME/.aws/config"
    AWS_CREDENTIALS_FILE="$HOME/.aws/credentials"

    # Check if files exist before we try to create them
    CONFIG_EXISTED=false
    CREDS_EXISTED=false
    
    if [ -f "$AWS_CONFIG_FILE" ]; then
        CONFIG_EXISTED=true
    fi
    
    if [ -f "$AWS_CREDENTIALS_FILE" ]; then
        CREDS_EXISTED=true
    fi

    # Create empty files if they don't exist
    touch "$AWS_CONFIG_FILE"
    touch "$AWS_CREDENTIALS_FILE"

    # A 'default' profile is required
    if ! grep -q '^\[profile default\]' "$AWS_CONFIG_FILE"; then
        echo "Default profile is not set. Adding it..."
        echo "[profile default]" >> "$AWS_CONFIG_FILE"
        echo "region = us-east-1" >> "$AWS_CONFIG_FILE"
        echo "output = json" >> "$AWS_CONFIG_FILE"
    fi
    if ! grep -q '^\[default\]' "$AWS_CREDENTIALS_FILE"; then
        echo "Default profile is not set. Adding it..."
        echo "[default]" >> "$AWS_CREDENTIALS_FILE"
        echo "manager = awsume" >> "$AWS_CREDENTIALS_FILE"
    fi
    
    # If we created the files from scratch, populate them with available profiles
    # This uses the repopulate_config function which will call:
    # aws-sso-util configure populate --region $DEFAULT_REGION --sso-region $SSO_REGION --sso-start-url $SSO_START_URL
    if [ "$CONFIG_EXISTED" = false ] || [ "$CREDS_EXISTED" = false ]; then
        echo "AWS config files were created. Populating with available profiles..."
        repopulate_config
    fi

    # Check if awsume is installed
    if ! command -v awsume &> /dev/null; then
        echo "awsume could not be found. Please install it with:"
        echo "pip install awsume"
        exit 1
    fi
    if ! command -v aws-sso-util &> /dev/null; then
        echo "aws-sso-util could not be found. Please install it with:"
        echo "pip install aws-sso-util"
        exit 1
    fi
    
    # Check if gum is installed
    if ! command -v gum &> /dev/null; then
        echo "gum is required but not found. Please install it with:"
        echo "brew install gum"
        exit 1
    fi
}

# Function to handle AWS SSO login
aws_sso_login() {
    # Check current login status
    output=$(aws-sso-util check)
    
    if [[ "$output" == *"Token appears to be valid for use"* ]]; then
        gum style \
            --foreground 2 \
            --bold --align center \
            "✓ You're already logged in to AWS SSO"
        
        # Ask if user wants to force re-login
        if gum confirm "Do you want to force a new login session?"; then
            perform_login
        else
            return 0
        fi
    else
        perform_login
    fi
}

# Helper function to perform the actual login
perform_login() {
    gum spin --spinner dot --title "Logging in to AWS SSO..." -- bash -c "
        aws-sso-util login --sso-start-url $SSO_START_URL --sso-region $SSO_REGION
        sleep 1
    "
    
    # Verify login was successful
    output=$(aws-sso-util check)
    if [[ "$output" == *"Token appears to be valid for use"* ]]; then
        gum style \
            --foreground 2 \
            --bold --align center \
            "✓ Successfully logged in to AWS SSO"
    else
        gum style \
            --foreground 1 \
            --bold --align center \
            "✗ Login to AWS SSO failed"
        return 1
    fi
}

# Function to repopulate AWS config
repopulate_config() {
    gum style \
        --foreground 4 --border normal --border-foreground 4 \
        --align center --width 70 \
        "This will repopulate your AWS config file with all available profiles"
    
    # Ask for confirmation before proceeding
    if ! gum confirm "Do you want to proceed?"; then
        gum style --foreground 3 "Operation cancelled."
        return 1
    fi
    
    # Show spinner while repopulating config
    gum spin --spinner dot --title "Repopulating AWS config..." -- bash -c "
        aws-sso-util configure populate --region $DEFAULT_REGION --sso-region $SSO_REGION --sso-start-url $SSO_START_URL
        sleep 1
    "
    
    # Show success message
    gum style \
        --foreground 2 \
        --bold --align center \
        "✓ Successfully repopulated AWS config"
    
    # Ask if user wants to switch profile now
    if gum confirm "Do you want to switch to a profile now?"; then
        switch_profile
    fi
}

switch_profile() {
    # aws-sso-util login if needed
    output=$(aws-sso-util check)
    if [[ "$output" != *"Token appears to be valid for use"* ]]; then
        gum style --foreground 3 "You need to login to AWS SSO first."
        if ! perform_login; then
            return 1
        fi
    fi

    # Get all the awsume managed profiles
    gum style --foreground 4 "Loading AWS profiles..."
    output=$(. awsume -l)
    
    # Parse profiles, excluding default - using a more compatible approach
    profile_list=()
    while read -r profile; do
        if [ -n "$profile" ] && [ "$profile" != "default" ]; then
            profile_list+=("$profile")
        fi
    done < <(echo "$output" | tail -n +5 | awk '{print $1}' | grep -v '^default$' | sort)

    if [ ${#profile_list[@]} -eq 0 ]; then
        gum style --foreground 1 "No profiles found."
        exit 1
    fi

    # Show a header
    gum style \
        --foreground 4 --border double --border-foreground 4 \
        --align center --width 50 \
        "AWS Profile Selection"
    
    # Use gum filter to select a profile
    selected_profile=$(printf "%s\n" "${profile_list[@]}" | \
        gum filter --placeholder "Choose a profile to assume..." \
        --height 15 --width 50 --prompt "› ")
    
    # Check if user cancelled
    if [ -z "$selected_profile" ]; then
        gum style --foreground 3 "Operation cancelled."
        return
    fi
    
    # Show confirmation
    gum confirm "Assume role: $selected_profile?" || {
        gum style --foreground 3 "Operation cancelled."
        return
    }
    
    # Show spinner while assuming role
    gum spin --spinner dot --title "Assuming AWS role: $selected_profile" -- bash -c "
        eval 'awsume $selected_profile -o default'
        sleep 1
    "
    
    # Export AWS credentials
    export AWS_PROFILE="default"
    export AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN"
    export AWS_SECURITY_TOKEN="$AWS_SECURITY_TOKEN"
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"

    # Show success message using gum
    echo ""
    gum style \
        --foreground 2 \
        --bold --align center \
        "✓ Successfully logged in as:"
    
    # Calculate width based on profile name length to ensure it fits
    profile_width=$((${#selected_profile} + 20))
    # Ensure minimum width
    if [ "$profile_width" -lt 60 ]; then
        profile_width=60
    fi
    
    # Display profile in a box with adequate width
    gum style \
        --foreground 5 --bold \
        --border normal --border-foreground 4 \
        --padding "1 2" --align center --width $profile_width \
        "$selected_profile"
    echo ""
}

# Function to update AWsome
update_awsome() {
    gum style \
        --foreground 4 --border normal --border-foreground 4 \
        --align center --width 70 \
        "This will update AWsome to the latest version"
    
    # Check if update script exists
    if ! command -v awsome-update &> /dev/null; then
        gum style --foreground 1 "Update script not found. You may need to reinstall AWsome."
        return 1
    fi
    
    # Ask for confirmation before proceeding
    if ! gum confirm "Do you want to proceed with the update?"; then
        gum style --foreground 3 "Update cancelled."
        return 1
    fi
    
    # Show spinner while updating
    gum spin --spinner dot --title "Updating AWsome..." -- bash -c "
        awsome-update
        sleep 1
    "
    
    # Show success message
    gum style \
        --foreground 2 \
        --bold --align center \
        "✓ AWsome has been updated to the latest version"
    
    # Ask if user wants to reload the script
    if gum confirm "Do you want to reload AWsome now?"; then
        gum style --foreground 4 "Please run the script again to use the updated version."
        return 0
    fi
}

# Show configuration information
show_config() {
    gum style \
        --foreground 4 --border normal --border-foreground 4 \
        --align center --width 70 \
        "AWsome Configuration"
    
    echo ""
    gum style --foreground 5 --bold "AWS Default Region:"
    gum style --foreground 6 "  $DEFAULT_REGION"
    
    echo ""
    gum style --foreground 5 --bold "AWS SSO Region:"
    gum style --foreground 6 "  $SSO_REGION"
    
    echo ""
    gum style --foreground 5 --bold "AWS SSO Start URL:"
    gum style --foreground 6 "  $SSO_START_URL"
    echo ""
    
    gum style --foreground 5 --bold "Configuration File:"
    gum style --foreground 6 "  $AWSOME_CONFIG_FILE"
    echo ""
    
    # Read update cache
    read_update_cache
    
    # Show update status section
    gum style --foreground 5 --bold "Update Status:"
    
    # Format timestamps to human-readable format - use cross-platform timestamp conversion
    format_timestamp() {
        local timestamp=$1
        if [ "$timestamp" -gt 0 ]; then
            # Try BSD style (macOS)
            if date -r "$timestamp" &>/dev/null; then
                date -r "$timestamp" "+%Y-%m-%d %H:%M:%S"
            # Try GNU style (Linux)
            elif date -d "@$timestamp" &>/dev/null; then
                date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S"
            else
                echo "Unknown date format"
            fi
        else
            echo "Never"
        fi
    }
    
    last_check_date=$(format_timestamp "$LAST_CHECK")
    gum style --foreground 6 "  Last check: $last_check_date"
    
    if [ "$LAST_SUCCESSFUL_CHECK" -gt 0 ] && [ "$LAST_SUCCESSFUL_CHECK" -ne "$LAST_CHECK" ]; then
        last_success_date=$(format_timestamp "$LAST_SUCCESSFUL_CHECK")
        gum style --foreground 6 "  Last successful check: $last_success_date"
    fi

    # Show update availability
    if [ "$BEHIND_COUNT" -gt 0 ]; then
        gum style --foreground 3 "  🚀 Updates available: $BEHIND_COUNT new changes"
    elif [ "$LAST_CHECK" -gt 0 ]; then
        gum style --foreground 2 "  ✓ Up to date"
    fi
    
    # Show next scheduled check
    if [ "$CACHE_EXPIRES_AT" -gt 0 ]; then
        next_check=$(format_timestamp "$CACHE_EXPIRES_AT")
        gum style --foreground 6 "  Next scheduled check: $next_check"
    fi
    
    # Show failed check info if relevant
    if [ "$FAILED_CHECKS" -gt 0 ]; then
        gum style --foreground 3 "  ⚠️ Failed update checks: $FAILED_CHECKS"
    fi
    
    echo ""
    
    gum style --foreground 4 "To change these settings, edit the configuration file at:"
    gum style --foreground 6 "  $AWSOME_CONFIG_FILE"
    echo ""
    
    # Wait for user to press key
    gum confirm "Press enter to return to menu" --affirmative "OK" --negative "" || true
}

# Main menu function
show_main_menu() {
    # Only check for updates if not already done
    # When called directly from main with no arguments, the check is already done
    if [ "$1" != "no_update_check" ]; then
        check_for_updates
    fi
    
    gum style \
        --foreground 4 --border double --border-foreground 4 \
        --align center --width 60 \
        "AWS Session Manager"
    
    # Check if logged in and display status
    output=$(aws-sso-util check 2>/dev/null)
    if [[ "$output" == *"Token appears to be valid for use"* ]]; then
        gum style \
            --foreground 2 --align center \
            "SSO Status: Logged In"
    else
        gum style \
            --foreground 3 --align center \
            "SSO Status: Not Logged In"
    fi
    
    echo ""
    
    # Show menu options
    selection=$(gum choose \
        --height 12 \
        --cursor.foreground 6 \
        --selected.foreground 6 \
        "1. Switch AWS Profile" \
        "2. Login to AWS SSO" \
        "3. Repopulate AWS Config" \
        "4. View Configuration" \
        "5. Update AWsome" \
        "6. Exit")
    
    case $selection in
        "1. Switch AWS Profile")
            switch_profile
            ;;
        "2. Login to AWS SSO")
            aws_sso_login
            ;;
        "3. Repopulate AWS Config")
            repopulate_config
            ;;
        "4. View Configuration")
            show_config
            ;;
        "5. Update AWsome")
            update_awsome
            ;;
        "6. Exit"|"")
            return
            ;;
    esac
}

# Function to force update check
force_update_check() {
    gum style \
        --foreground 4 --border normal --border-foreground 4 \
        --align center --width 70 \
        "Checking for AWsome updates..."
    
    # Force a complete update check
    local current_time=$(date +%s)
    
    # Check pre-requisites
    if ! command -v git &> /dev/null; then
        gum style --foreground 3 "Git is not installed. Unable to check for updates."
        return 1
    fi
    
    # Check if repo directory exists
    if [ ! -d "$REPO_DIR" ]; then
        gum style --foreground 3 "Repository directory not found at $REPO_DIR."
        return 1
    fi
    
    # Check if it's a git repo
    if [ ! -d "$REPO_DIR/.git" ]; then
        gum style --foreground 3 "Not a git repository at $REPO_DIR."
        return 1
    fi
    
    # Try to access the repo directory
    if ! cd "$REPO_DIR" 2>/dev/null; then
        gum style --foreground 3 "Cannot access repository directory. Check permissions."
        return 1
    fi
    
    # Verify we can get the current HEAD (basic git operations work)
    local_head=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    if [ "$local_head" = "unknown" ]; then
        gum style --foreground 3 "Unable to read git repository state."
        return 1
    fi
    
    # Check remote configuration
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$remote_url" ]; then
        gum style --foreground 3 "No remote 'origin' configured in git repository."
        return 1
    fi
    
    # Show spinner while checking for updates
    fetch_success=false
    gum spin --spinner dot --title "Fetching latest updates..." -- bash -c "
        # Try to fetch with a timeout
        if timeout $GIT_TIMEOUT git fetch origin 2>/dev/null; then
            echo 'success' > /tmp/awsome_fetch_result
        else
            echo 'fail' > /tmp/awsome_fetch_result
        fi
    "
    
    # Check fetch result
    if [ -f "/tmp/awsome_fetch_result" ] && [ "$(cat /tmp/awsome_fetch_result)" = "success" ]; then
        fetch_success=true
        rm -f "/tmp/awsome_fetch_result" 2>/dev/null
    else
        rm -f "/tmp/awsome_fetch_result" 2>/dev/null
    fi
    
    if ! $fetch_success; then
        gum style --foreground 1 "Failed to fetch updates. Network issue or remote repository unavailable."
        return 1
    fi
    
    # Try to get the remote head
    if ! git rev-parse origin/main &>/dev/null; then
        # If main branch doesn't exist, try master
        if ! git rev-parse origin/master &>/dev/null; then
            gum style --foreground 3 "Cannot find main or master branch on remote."
            return 1
        else
            remote_branch="master"
        fi
    else
        remote_branch="main"
    fi
    
    # Get the latest commit information
    new_remote_head=$(git rev-parse origin/$remote_branch 2>/dev/null || echo "unknown")
    if [ "$new_remote_head" = "unknown" ]; then
        gum style --foreground 3 "Unable to determine remote version."
        return 1
    fi
    
    # Check if we're behind the remote
    new_behind_count=$(git rev-list HEAD..origin/$remote_branch --count 2>/dev/null || echo "0")
    
    # Reset failed checks counter and update cache
    FAILED_CHECKS=0
    write_update_cache "$current_time" "$new_behind_count" "$new_remote_head"
    
    # Show appropriate message
    if [ "$new_behind_count" -gt 0 ]; then
        gum style \
            --foreground 3 --bold --align center \
            "🚀 Update Available! There are $new_behind_count new changes available."
        
        # Ask if user wants to update now
        if gum confirm "Would you like to update AWsome now?"; then
            update_awsome
        fi
    else
        gum style \
            --foreground 2 --bold --align center \
            "✓ AWsome is up to date!"
    fi
}

# Temporary file to track if we've shown the update banner recently
UPDATE_BANNER_SHOWN_FILE="/tmp/awsome_update_banner_shown"
UPDATE_BANNER_SHOWN_TIMEOUT=30 # seconds

# Function to check if update banner was recently shown
update_banner_shown() {
    # If the file doesn't exist, banner hasn't been shown
    if [ ! -f "$UPDATE_BANNER_SHOWN_FILE" ]; then
        return 1 # false
    fi
    
    # Check if the file is recent (within timeout period)
    file_time=$(stat -c %Y "$UPDATE_BANNER_SHOWN_FILE" 2>/dev/null || stat -f %m "$UPDATE_BANNER_SHOWN_FILE" 2>/dev/null)
    current_time=$(date +%s)
    
    # If file time couldn't be read or file is older than timeout, consider banner not shown
    if [ -z "$file_time" ] || [ "$((current_time - file_time))" -gt "$UPDATE_BANNER_SHOWN_TIMEOUT" ]; then
        return 1 # false
    fi
    
    return 0 # true - banner was recently shown
}

# Function to mark the update banner as shown
mark_update_banner_shown() {
    # Create or touch the file to update its timestamp
    touch "$UPDATE_BANNER_SHOWN_FILE" 2>/dev/null
}

# Process command line arguments
process_args() {
    # Check if this is a direct update check request
    if [[ "$1" == "update" || "$1" == "u" ]] && [[ "$2" == "--check" || "$2" == "-c" ]]; then
        force_update_check
        return
    fi
    
    # Normal update check for all other commands
    check_for_updates

    case "$1" in
        "profile"|"p"|"")  # Default behavior is to switch profile
            switch_profile
            ;;
        "login"|"l")  # Login to SSO
            aws_sso_login
            ;;
        "repopulate"|"r")  # Repopulate config
            repopulate_config
            ;;
        "config"|"c")  # Show configuration
            show_config
            ;;
        "update"|"u")  # Update AWsome
            update_awsome
            ;;
        "menu"|"m")  # Show menu
            show_main_menu
            ;;
        "help"|"h"|"-h"|"--help")
            echo "AWS Session Manager - Usage:"
            echo "  $(basename "$0")              - Switch AWS profiles (default)"
            echo "  $(basename "$0") p|profile    - Switch AWS profiles"
            echo "  $(basename "$0") l|login      - Login to AWS SSO"
            echo "  $(basename "$0") r|repopulate - Repopulate AWS config"
            echo "  $(basename "$0") c|config     - View configuration settings"
            echo "  $(basename "$0") u|update     - Update AWsome to latest version"
            echo "  $(basename "$0") u|update -c  - Check for AWsome updates"
            echo "  $(basename "$0") m|menu       - Show interactive menu"
            echo "  $(basename "$0") h|help       - Show this help message"
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use '$(basename "$0") help' for usage information"
            return 1
            ;;
    esac
}

# Main execution
precheck

# Process arguments regardless of whether the script is sourced or executed directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is sourced (credentials will be exported to current shell)
    process_args "$@"
else
    # Script is executed directly (useful for UI operations but credentials won't be exported)
    if [[ $# -eq 0 ]]; then
        # No arguments provided, do a single check for updates then show the menu
        check_for_updates
        show_main_menu "no_update_check"
    else
        # Arguments provided, process them
        process_args "$@"
    fi
fi
