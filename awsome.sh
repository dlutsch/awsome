#!/bin/bash

# AWS Session Manager (AWsome)
# https://github.com/dlutsch/awsome
#
# MIT License
# Copyright (c) 2025 dlutsch
# See LICENSE file for full license text
#
# Configuration values - these will be set during installation
DEFAULT_REGION="us-west-2"  # AWS Default Region
SSO_REGION="us-west-2"      # SSO Region - Same as DEFAULT_REGION by default
SSO_START_URL=""            # SSO Start URL - No default value

precheck() {
    # Create AWS config directory if it doesn't exist
    mkdir -p "$HOME/.aws"
    
    # Path to AWS config file
    AWS_CONFIG_FILE="$HOME/.aws/config"
    AWS_CREDENTIALS_FILE="$HOME/.aws/credentials"

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
        exit 0
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
    
    gum style --foreground 4 "To change these settings, reinstall AWsome with the"
    gum style --foreground 4 "appropriate environment variables set."
    echo ""
    
    # Wait for user to press key
    gum confirm "Press enter to return to menu" --affirmative "OK" --negative "" || true
}

# Main menu function
show_main_menu() {
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

# Process command line arguments
process_args() {
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
        # No arguments provided, show the menu
        show_main_menu
    else
        # Arguments provided, process them
        process_args "$@"
    fi
fi
