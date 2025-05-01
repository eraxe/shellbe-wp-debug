#!/bin/bash
#
# WordPress Debug Plugin - Post-connection Hook
# Executed after an SSH connection is closed
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
EXIT_CODE="$5"

# Only proceed if the connection was successful
if [ "$EXIT_CODE" -eq 0 ]; then
    # Check if WordPress path is saved for this profile
    DEFAULT_WP_PATH=$(get_default_wp_installation "$PROFILE_NAME")
    
    if [ -n "$DEFAULT_WP_PATH" ]; then
        # Check if debugging is enabled
        DEBUG_STATUS=$(get_debug_setting "$PROFILE_NAME" "$DEFAULT_WP_PATH" "WP_DEBUG")
        DEBUG_LOG=$(get_debug_setting "$PROFILE_NAME" "$DEFAULT_WP_PATH" "WP_DEBUG_LOG")
        
        if [ "$DEBUG_STATUS" = "true" ] && ([ "$DEBUG_LOG" = "true" ] || [[ "$DEBUG_LOG" =~ ^[\"\']/.*[\"\']$ ]]); then
            # Get log path
            LOG_PATH=$(get_debug_log_path "$PROFILE_NAME" "$DEFAULT_WP_PATH")
            
            # Check if there are new entries in the log
            CHECK_CMD="[ -f \"$LOG_PATH\" ] && stat -c %s \"$LOG_PATH\" || echo '0'"
            LOG_SIZE=$(shellbe_ssh_command "$PROFILE_NAME" "$CHECK_CMD")
            
            if [ "$LOG_SIZE" -gt 0 ]; then
                echo -e "\033[0;33m[WP-DEBUG]\033[0m WordPress debug log has entries. View with:"
                echo -e "\033[0;36mshellbe wpd $PROFILE_NAME log\033[0m"
            fi
        fi
        
        # Check if it's a production site with debugging enabled
        if [ "$DEBUG_STATUS" = "true" ] && is_production_site "$PROFILE_NAME" "$DEFAULT_WP_PATH"; then
            echo -e "\033[0;31m[WP-DEBUG WARNING]\033[0m Remember to disable debugging on this production site:"
            echo -e "\033[0;36mshellbe wpd $PROFILE_NAME disable\033[0m"
        fi
    else
        # Check if there are any WordPress installations with debugging enabled
        WP_INSTALLATIONS=$(get_wp_installations "$PROFILE_NAME")
        
        if [ -n "$WP_INSTALLATIONS" ]; then
            # Check if any installations have debugging enabled on production
            PROD_DEBUG_ENABLED=false
            
            while IFS= read -r WP_PATH; do
                DEBUG_STATUS=$(get_debug_setting "$PROFILE_NAME" "$WP_PATH" "WP_DEBUG")
                
                if [ "$DEBUG_STATUS" = "true" ] && is_production_site "$PROFILE_NAME" "$WP_PATH"; then
                    PROD_DEBUG_ENABLED=true
                    break
                fi
            done <<< "$WP_INSTALLATIONS"
            
            if [ "$PROD_DEBUG_ENABLED" = true ]; then
                echo -e "\033[0;31m[WP-DEBUG WARNING]\033[0m Production site(s) with debugging enabled!"
                echo -e "\033[0;33m[WP-DEBUG]\033[0m Use 'shellbe wpd $PROFILE_NAME' to manage WordPress debugging"
            fi
        fi
    fi
    
    # Check if we have any newly discovered WordPress installations
    if ! [ -f "$PLUGIN_DIR/.last_check_$PROFILE_NAME" ]; then
        touch "$PLUGIN_DIR/.last_check_$PROFILE_NAME"
    fi
    
    # Get last check time
    LAST_CHECK=$(stat -c %Y "$PLUGIN_DIR/.last_check_$PROFILE_NAME")
    CURRENT_TIME=$(date +%s)
    
    # Only check for new WordPress installations every 7 days
    if [ $((CURRENT_TIME - LAST_CHECK)) -gt 604800 ]; then
        echo -e "\033[0;33m[WP-DEBUG]\033[0m Checking for new WordPress installations..."
        
        # Get current installations
        CURRENT_WP=$(get_wp_installations "$PROFILE_NAME" | wc -l)
        
        # Find new installations
        DEFAULT_SEARCH_PATHS=$(grep "^default_search_paths=" "$PLUGIN_DIR/config.ini" | cut -d= -f2)
        MAX_SEARCH_DEPTH=$(grep "^max_search_depth=" "$PLUGIN_DIR/config.ini" | cut -d= -f2)
        
        if [ -z "$DEFAULT_SEARCH_PATHS" ]; then
            DEFAULT_SEARCH_PATHS="/var/www/html,/srv/www,/home"
        fi
        
        if [ -z "$MAX_SEARCH_DEPTH" ]; then
            MAX_SEARCH_DEPTH=5
        fi
        
        NEW_WP=$(shellbe_ssh_command "$PROFILE_NAME" "find $DEFAULT_SEARCH_PATHS -type f -name wp-config.php -maxdepth $MAX_SEARCH_DEPTH 2>/dev/null" | wc -l)
        
        if [ "$NEW_WP" -gt "$CURRENT_WP" ]; then
            echo -e "\033[0;33m[WP-DEBUG]\033[0m Found $(($NEW_WP - $CURRENT_WP)) new WordPress installation(s)!"
            echo -e "\033[0;33m[WP-DEBUG]\033[0m Use 'shellbe wpd $PROFILE_NAME find' to update your installation list"
        fi
        
        # Update check time
        touch "$PLUGIN_DIR/.last_check_$PROFILE_NAME"
    fi
fi

exit 0
