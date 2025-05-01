#!/bin/bash
#
# WordPress Debug Plugin - Profile Info Hook
# Executed when profile information is shown
#

# Get plugin directory
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source library functions
source "$PLUGIN_DIR/lib.sh"

# Parse arguments
PROFILE_NAME="$1"
HOST="$2"
USER="$3"
PORT="$4"

# Check for WordPress installations
WP_INSTALLATIONS=$(get_wp_installations "$PROFILE_NAME")
DEFAULT_WP_PATH=$(get_default_wp_installation "$PROFILE_NAME")

if [ -n "$WP_INSTALLATIONS" ]; then
    # Count installations
    WP_COUNT=$(echo "$WP_INSTALLATIONS" | wc -l)
    
    echo -e "\033[0;34m[WPD] WordPress Information:${NC}"
    echo -e "\033[0;36mInstallations:${NC}\t$WP_COUNT found"
    
    # Show default installation if set
    if [ -n "$DEFAULT_WP_PATH" ]; then
        echo -e "\033[0;36mDefault WP:${NC}\t$DEFAULT_WP_PATH"
        
        # Get WordPress version
        WP_VERSION=$(get_wp_version "$PROFILE_NAME" "$DEFAULT_WP_PATH")
        echo -e "\033[0;36mWP Version:${NC}\t$WP_VERSION"
        
        # Try to get site name
        SITE_NAME=$(get_wp_site_name "$PROFILE_NAME" "$DEFAULT_WP_PATH")
        if [ -n "$SITE_NAME" ]; then
            echo -e "\033[0;36mSite Name:${NC}\t$SITE_NAME"
        fi
        
        # Check debugging status
        DEBUG_STATUS=$(get_debug_setting "$PROFILE_NAME" "$DEFAULT_WP_PATH" "WP_DEBUG")
        DEBUG_LOG=$(get_debug_setting "$PROFILE_NAME" "$DEFAULT_WP_PATH" "WP_DEBUG_LOG")
        
        if [ "$DEBUG_STATUS" = "true" ]; then
            echo -e "\033[0;36mDebugging:${NC}\t\033[0;32mEnabled\033[0m"
            
            if [ "$DEBUG_LOG" = "true" ] || [[ "$DEBUG_LOG" =~ ^[\"\']/.*[\"\']$ ]]; then
                LOG_PATH=$(get_debug_log_path "$PROFILE_NAME" "$DEFAULT_WP_PATH")
                LOG_EXISTS=$(shellbe_ssh_command "$PROFILE_NAME" "[ -f \"$LOG_PATH\" ] && echo 'yes' || echo 'no'")
                
                if [ "$LOG_EXISTS" = "yes" ]; then
                    LOG_SIZE=$(shellbe_ssh_command "$PROFILE_NAME" "ls -lh \"$LOG_PATH\" | awk '{print \$5}'")
                    echo -e "\033[0;36mDebug Log:${NC}\t$LOG_PATH ($LOG_SIZE)"
                else
                    echo -e "\033[0;36mDebug Log:${NC}\t$LOG_PATH (not created yet)"
                fi
            fi
        else
            echo -e "\033[0;36mDebugging:${NC}\t\033[0;31mDisabled\033[0m"
        fi
        
        # Check if it's a production site
        if is_production_site "$PROFILE_NAME" "$DEFAULT_WP_PATH"; then
            echo -e "\033[0;36mEnvironment:${NC}\t\033[0;31mProduction\033[0m"
            
            if [ "$DEBUG_STATUS" = "true" ]; then
                echo -e "\033[0;31m[WARNING] Debugging is enabled on a production site!\033[0m"
            fi
        else
            echo -e "\033[0;36mEnvironment:${NC}\t\033[0;32mDevelopment/Staging\033[0m"
        fi
    fi
    
    echo -e "\033[0;36mManage:${NC}\t\tshellbe wpd $PROFILE_NAME"
fi

exit 0
