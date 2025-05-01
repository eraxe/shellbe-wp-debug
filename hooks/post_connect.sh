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

# Validate required arguments
if [ -z "$PROFILE_NAME" ]; then
    echo -e "\033[0;31m[WP-DEBUG Error]\033[0m Missing profile name" >&2
    exit 1
fi

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
            
            # Create a temporary script to check log size
            local temp_script="/tmp/wpd_check_log_size_${RANDOM}.sh"
            cat > "$temp_script" << EOF
#!/bin/bash
if [ -f "$LOG_PATH" ]; then
    stat -c %s "$LOG_PATH" 2>/dev/null || echo '0'
else
    echo '0'
fi
EOF
            chmod +x "$temp_script"
            
            # Copy script to remote server
            local remote_script="/tmp/wpd_check_log_size_${RANDOM}.sh"
            shellbe_ssh_command "$PROFILE_NAME" "cat > \"$remote_script\"" < "$temp_script"
            shellbe_ssh_command "$PROFILE_NAME" "chmod +x \"$remote_script\"" > /dev/null 2>&1
            
            # Execute the script on the remote server
            LOG_SIZE=$(shellbe_ssh_command "$PROFILE_NAME" "bash \"$remote_script\"")
            
            # Clean up temporary files
            rm -f "$temp_script"
            shellbe_ssh_command "$PROFILE_NAME" "rm -f \"$remote_script\"" > /dev/null 2>&1
            
            if [ "$LOG_SIZE" -gt 0 ] 2>/dev/null; then
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
                if [ -n "$WP_PATH" ]; then  # Skip empty lines
                    DEBUG_STATUS=$(get_debug_setting "$PROFILE_NAME" "$WP_PATH" "WP_DEBUG")
                    
                    if [ "$DEBUG_STATUS" = "true" ] && is_production_site "$PROFILE_NAME" "$WP_PATH"; then
                        PROD_DEBUG_ENABLED=true
                        break
                    fi
                fi
            done <<< "$WP_INSTALLATIONS"
            
            if [ "$PROD_DEBUG_ENABLED" = true ]; then
                echo -e "\033[0;31m[WP-DEBUG WARNING]\033[0m Production site(s) with debugging enabled!"
                echo -e "\033[0;33m[WP-DEBUG]\033[0m Use 'shellbe wpd $PROFILE_NAME' to manage WordPress debugging"
            fi
        fi
    fi
    
    # Check if we have any newly discovered WordPress installations
    LAST_CHECK_FILE="$PLUGIN_DIR/.last_check_$PROFILE_NAME"
    
    if ! [ -f "$LAST_CHECK_FILE" ]; then
        touch "$LAST_CHECK_FILE" || {
            echo -e "\033[0;31m[WP-DEBUG Error]\033[0m Failed to create check file" >&2
            exit 1
        }
    fi
    
    # Get last check time, with error handling
    if ! LAST_CHECK=$(stat -c %Y "$LAST_CHECK_FILE" 2>/dev/null); then
        LAST_CHECK=0
    fi
    
    CURRENT_TIME=$(date +%s)
    
    # Only check for new WordPress installations every 7 days
    if [ $((CURRENT_TIME - LAST_CHECK)) -gt 604800 ]; then
        echo -e "\033[0;33m[WP-DEBUG]\033[0m Checking for new WordPress installations..."
        
        # Get current installations
        CURRENT_WP_COUNT=0
        CURRENT_WP=$(get_wp_installations "$PROFILE_NAME")
        
        if [ -n "$CURRENT_WP" ]; then
            CURRENT_WP_COUNT=$(echo "$CURRENT_WP" | wc -l)
        fi
        
        # Find new installations
        CONFIG_FILE="$PLUGIN_DIR/config.ini"
        DEFAULT_SEARCH_PATHS="/var/www/html,/srv/www,/home"
        MAX_SEARCH_DEPTH=5
        
        if [ -f "$CONFIG_FILE" ]; then
            DEFAULT_SEARCH_PATHS=$(grep "^default_search_paths=" "$CONFIG_FILE" | cut -d= -f2)
            MAX_SEARCH_DEPTH=$(grep "^max_search_depth=" "$CONFIG_FILE" | cut -d= -f2)
        fi
        
        if [ -z "$DEFAULT_SEARCH_PATHS" ]; then
            DEFAULT_SEARCH_PATHS="/var/www/html,/srv/www,/home"
        fi
        
        if [ -z "$MAX_SEARCH_DEPTH" ] || ! [[ "$MAX_SEARCH_DEPTH" =~ ^[0-9]+$ ]]; then
            MAX_SEARCH_DEPTH=5
        fi
        
        # Safely sanitize search paths to prevent command injection
        DEFAULT_SEARCH_PATHS=$(echo "$DEFAULT_SEARCH_PATHS" | tr -d ';&|$()')
        
        # Create a temporary script to count WordPress installations
        local count_script="/tmp/wpd_count_wp_${RANDOM}.sh"
        cat > "$count_script" << EOF
#!/bin/bash
find $DEFAULT_SEARCH_PATHS -type f -name wp-config.php -maxdepth $MAX_SEARCH_DEPTH 2>/dev/null | wc -l
EOF
        chmod +x "$count_script"
        
        # Copy script to remote server
        local remote_count_script="/tmp/wpd_count_wp_${RANDOM}.sh"
        shellbe_ssh_command "$PROFILE_NAME" "cat > \"$remote_count_script\"" < "$count_script"
        shellbe_ssh_command "$PROFILE_NAME" "chmod +x \"$remote_count_script\"" > /dev/null 2>&1
        
        # Execute the script on the remote server
        NEW_WP=$(shellbe_ssh_command "$PROFILE_NAME" "bash \"$remote_count_script\"")
        
        # Clean up temporary files
        rm -f "$count_script"
        shellbe_ssh_command "$PROFILE_NAME" "rm -f \"$remote_count_script\"" > /dev/null 2>&1
        
        # Handle potential errors
        if ! [[ "$NEW_WP" =~ ^[0-9]+$ ]]; then
            NEW_WP=0
        fi
        
        if [ "$NEW_WP" -gt "$CURRENT_WP_COUNT" ]; then
            echo -e "\033[0;33m[WP-DEBUG]\033[0m Found $(($NEW_WP - $CURRENT_WP_COUNT)) new WordPress installation(s)!"
            echo -e "\033[0;33m[WP-DEBUG]\033[0m Use 'shellbe wpd $PROFILE_NAME find' to update your installation list"
        fi
        
        # Update check time
        touch "$LAST_CHECK_FILE" || {
            echo -e "\033[0;31m[WP-DEBUG Error]\033[0m Failed to update check file" >&2
            exit 1
        }
    fi
fi

exit 0