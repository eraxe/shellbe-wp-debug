#!/bin/bash
#
# WordPress Debug Plugin - Cleanup Script
# Run when the plugin is disabled
#

set -e  # Exit on error

# Get plugin directory
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library functions
source "$PLUGIN_DIR/lib.sh"

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}Cleaning up WordPress Debug Plugin (WPD)...${NC}"

# Check for any active debugging sessions
if [ -f "$PLUGIN_DIR/wp_paths.ini" ] && [ -f "$PLUGIN_DIR/default_wp.ini" ]; then
    echo -e "${YELLOW}Checking for active debugging sessions...${NC}"
    
    # Read default WordPress installations
    if [ -f "$PLUGIN_DIR/default_wp.ini" ]; then
        while IFS== read -r profile path; do
            if [ -n "$profile" ] && [ -n "$path" ]; then
                # Check if debugging is enabled
                debug_status=$(get_debug_setting "$profile" "$path" "WP_DEBUG" 2>/dev/null)
                
                if [ "$debug_status" = "true" ]; then
                    echo -e "${YELLOW}Profile '$profile' has debugging enabled at:${NC}"
                    echo -e "  ${CYAN}$path${NC}"
                    
                    # Check if it's a production site
                    if is_production_site "$profile" "$path" 2>/dev/null; then
                        echo -e "  ${RED}WARNING: This appears to be a PRODUCTION site!${NC}"
                        
                        read -p "  Disable debugging before disabling the plugin? (y/n): " disable_debug
                        if [[ "$disable_debug" == "y" || "$disable_debug" == "Y" ]]; then
                            # Disable debugging
                            if set_debug_setting "$profile" "$path" "WP_DEBUG" "false" && \
                               set_debug_setting "$profile" "$path" "WP_DEBUG_LOG" "false" && \
                               set_debug_setting "$profile" "$path" "WP_DEBUG_DISPLAY" "false" && \
                               set_debug_setting "$profile" "$path" "SCRIPT_DEBUG" "false" && \
                               set_debug_setting "$profile" "$path" "SAVEQUERIES" "false"; then
                                echo -e "  ${GREEN}Debugging disabled successfully.${NC}"
                            else
                                echo -e "  ${RED}Failed to disable debugging. Please disable it manually.${NC}"
                                echo -e "  ${YELLOW}Use 'shellbe wpd $profile disable' to disable debugging${NC}"
                            fi
                        else
                            echo -e "  ${YELLOW}Leaving debugging enabled. Make sure to disable it manually!${NC}"
                            echo -e "  ${YELLOW}Use 'shellbe wpd $profile disable' to disable debugging${NC}"
                        fi
                    fi
                fi
            fi
        done < "$PLUGIN_DIR/default_wp.ini"
    fi
fi

# Backup configuration files
echo -e "${YELLOW}Backing up configuration files...${NC}"
backup_dir="$PLUGIN_DIR/backup_$(date +%Y%m%d%H%M%S)"
if mkdir -p "$backup_dir"; then
    backup_success=true
    
    for config_file in "$PLUGIN_DIR/config.ini" "$PLUGIN_DIR/wp_paths.ini" "$PLUGIN_DIR/default_wp.ini"; do
        if [ -f "$config_file" ]; then
            if ! cp "$config_file" "$backup_dir/"; then
                echo -e "${RED}Warning: Failed to backup $config_file${NC}" >&2
                backup_success=false
            fi
        fi
    done
    
    if [ "$backup_success" = true ]; then
        echo -e "${GREEN}Configurations backed up to: $backup_dir${NC}"
    else
        echo -e "${YELLOW}Some configuration files could not be backed up${NC}"
    fi
    
    echo -e "${YELLOW}Note: Your settings will be preserved for when you re-enable the plugin.${NC}"
else
    echo -e "${RED}Error: Failed to create backup directory${NC}" >&2
fi

# Remove temporary files
echo -e "${YELLOW}Removing temporary files...${NC}"
for temp_file in "$PLUGIN_DIR/.last_check_"*; do
    if [ -f "$temp_file" ]; then
        if ! rm -f "$temp_file"; then
            echo -e "${RED}Warning: Failed to remove temporary file: $temp_file${NC}" >&2
        fi
    fi
done

# Remove symbolic link if exists
SHELLBE_PLUGINS_DIR="$HOME/.shellbe/plugins"
if [ -d "$SHELLBE_PLUGINS_DIR" ] && [ -L "$SHELLBE_PLUGINS_DIR/wpd" ]; then
    if rm "$SHELLBE_PLUGINS_DIR/wpd"; then
        echo -e "${GREEN}Removed symbolic link${NC}"
    else
        echo -e "${RED}Warning: Failed to remove symbolic link${NC}" >&2
    fi
fi

echo -e "${GREEN}WordPress Debug Plugin (WPD) cleanup completed!${NC}"
echo -e "${YELLOW}If you need to manage WordPress debugging, re-enable the plugin with:${NC}"
echo -e "${CYAN}shellbe plugin enable wpd${NC}"