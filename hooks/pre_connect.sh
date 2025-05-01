#!/bin/bash
#
# WordPress Debug Plugin - Pre-connection Hook
# Executed before establishing an SSH connection
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

# Validate required arguments
if [ -z "$PROFILE_NAME" ]; then
    echo -e "\033[0;31m[WP-DEBUG Error]\033[0m Missing profile name" >&2
    exit 1
fi

# Check if WordPress path is saved for this profile
DEFAULT_WP_PATH=$(get_default_wp_installation "$PROFILE_NAME")

if [ -n "$DEFAULT_WP_PATH" ]; then
    # Display a message before connecting
    echo -e "\033[0;34m[WP-DEBUG]\033[0m Default WordPress found at: $DEFAULT_WP_PATH"
    
    # Check if debugging is enabled
    DEBUG_STATUS=$(get_debug_setting "$PROFILE_NAME" "$DEFAULT_WP_PATH" "WP_DEBUG")
    
    if [ "$DEBUG_STATUS" = "true" ]; then
        echo -e "\033[0;33m[WP-DEBUG]\033[0m WordPress debugging is currently \033[0;32mENABLED\033[0m"
        
        # Check if it's a production site
        if is_production_site "$PROFILE_NAME" "$DEFAULT_WP_PATH"; then
            echo -e "\033[0;31m[WP-DEBUG WARNING]\033[0m This appears to be a PRODUCTION site with debugging enabled!"
            echo -e "\033[0;33m[WP-DEBUG]\033[0m Use 'shellbe wpd $PROFILE_NAME disable' to disable debugging"
        fi
    else
        echo -e "\033[0;33m[WP-DEBUG]\033[0m WordPress debugging is currently \033[0;31mDISABLED\033[0m"
    fi
else
    # Check if there are any WordPress installations for this profile
    WP_INSTALLATIONS=$(get_wp_installations "$PROFILE_NAME")
    
    if [ -n "$WP_INSTALLATIONS" ]; then
        # Count installations
        WP_COUNT=$(echo "$WP_INSTALLATIONS" | wc -l)
        
        echo -e "\033[0;34m[WP-DEBUG]\033[0m Found $WP_COUNT WordPress installation(s) on this server"
        echo -e "\033[0;33m[WP-DEBUG]\033[0m Use 'shellbe wpd $PROFILE_NAME' to manage WordPress debugging"
        
        # Check if any installations have debugging enabled
        DEBUG_ENABLED=false
        
        while IFS= read -r WP_PATH; do
            if [ -n "$WP_PATH" ]; then  # Skip empty lines
                DEBUG_STATUS=$(get_debug_setting "$PROFILE_NAME" "$WP_PATH" "WP_DEBUG")
                
                if [ "$DEBUG_STATUS" = "true" ]; then
                    DEBUG_ENABLED=true
                    
                    # Check if it's a production site
                    if is_production_site "$PROFILE_NAME" "$WP_PATH"; then
                        echo -e "\033[0;31m[WP-DEBUG WARNING]\033[0m Production site with debugging enabled at: $WP_PATH"
                    else
                        echo -e "\033[0;33m[WP-DEBUG]\033[0m Debugging enabled at: $WP_PATH"
                    fi
                fi
            fi
        done <<< "$WP_INSTALLATIONS"
        
        if [ "$DEBUG_ENABLED" = false ]; then
            echo -e "\033[0;33m[WP-DEBUG]\033[0m No WordPress installations have debugging enabled"
        fi
    fi
fi

exit 0