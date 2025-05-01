#!/bin/bash
#
# WordPress Debug Plugin for ShellBe
# This plugin helps manage WordPress debugging settings on remote servers
#

# Get the plugin directory
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library functions
source "$PLUGIN_DIR/lib.sh" || {
    echo -e "${RED}Error: Failed to load library functions${NC}" >&2
    exit 1
}

# Define configuration file paths
CONFIG_FILE="$PLUGIN_DIR/config.ini"
DEFAULT_CONFIG_FILE="$PLUGIN_DIR/default_wp.ini"
WP_PATHS_FILE="$PLUGIN_DIR/wp_paths.ini"
TEMPLATES_DIR="$PLUGIN_DIR/templates"

# Create templates directory if it doesn't exist
if [ ! -d "$TEMPLATES_DIR" ]; then
    mkdir -p "$TEMPLATES_DIR/php" || {
        echo -e "${RED}Error: Failed to create templates directory${NC}" >&2
        exit 1
    }
    chmod 755 "$TEMPLATES_DIR" "$TEMPLATES_DIR/php"
}

# Initialize configuration if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << EOF
# WordPress Debug Plugin Configuration
# Generated: $(date +"%Y-%m-%d %H:%M:%S")
default_search_paths=/var/www/html,/srv/www,/home
max_search_depth=5
backup_before_changes=true
debug_log_limit=1000
EOF
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create configuration file${NC}" >&2
        exit 1
    fi
fi

# Create required files if they don't exist
for file in "$DEFAULT_CONFIG_FILE" "$WP_PATHS_FILE"; do
    if [ ! -f "$file" ]; then
        touch "$file" || {
            echo -e "${RED}Error: Failed to create required file: $file${NC}" >&2
            exit 1
        }
    fi
done

# Load configuration settings
load_config_setting() {
    local setting="$1"
    local default="$2"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "$default"
        return 0
    fi
    
    local value=$(grep "^$setting=" "$CONFIG_FILE" | cut -d= -f2-)
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

DEFAULT_SEARCH_PATHS=$(load_config_setting "default_search_paths" "/var/www/html,/srv/www,/home")
MAX_SEARCH_DEPTH=$(load_config_setting "max_search_depth" "5")
BACKUP_BEFORE_CHANGES=$(load_config_setting "backup_before_changes" "true")
DEBUG_LOG_LIMIT=$(load_config_setting "debug_log_limit" "1000")

# Validate MAX_SEARCH_DEPTH is a number
if ! [[ "$MAX_SEARCH_DEPTH" =~ ^[0-9]+$ ]]; then
    MAX_SEARCH_DEPTH=5
fi

# Validate DEBUG_LOG_LIMIT is a number
if ! [[ "$DEBUG_LOG_LIMIT" =~ ^[0-9]+$ ]]; then
    DEBUG_LOG_LIMIT=1000
fi

# Usage function
show_usage() {
    echo -e "${BLUE}WordPress Debug Plugin for ShellBe${NC}"
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  ${CYAN}shellbe wpd${NC}                                   Interactive mode"
    echo -e "  ${CYAN}shellbe wpd <profile>${NC}                         Interactive mode for specific server"
    echo -e "  ${CYAN}shellbe wpd <profile> <command> [options]${NC}     Direct command execution"
    echo
    echo -e "${YELLOW}Commands:${NC}"
    echo -e "  ${CYAN}find${NC}             Find wp-config.php files on a remote server"
    echo -e "  ${CYAN}list${NC}             List WordPress installations on a server"
    echo -e "  ${CYAN}status${NC}           Check WordPress debugging status"
    echo -e "  ${CYAN}enable${NC}           Enable WordPress debugging"
    echo -e "  ${CYAN}disable${NC}          Disable WordPress debugging"
    echo -e "  ${CYAN}log${NC}              View WordPress debug log"
    echo -e "  ${CYAN}configure${NC}        Configure WordPress debugging settings"
    echo -e "  ${CYAN}default${NC}          Set default WordPress installation for a server"
    echo -e "  ${CYAN}config${NC}           Configure plugin settings"
    echo -e "  ${CYAN}help${NC}             Show this help message"
    echo
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${CYAN}--path=<path>${NC}                   Specify the path to wp-config.php"
    echo -e "  ${CYAN}--search=<paths>${NC}                Comma-separated list of paths to search"
    echo -e "  ${CYAN}--depth=<number>${NC}                Maximum search depth (default: $MAX_SEARCH_DEPTH)"
    echo -e "  ${CYAN}--save-path${NC}                     Save found path for future use"
    echo -e "  ${CYAN}--debug-log=<path>${NC}              Specify custom debug log path"
    echo -e "  ${CYAN}--limit=<lines>${NC}                 Limit log output to specified lines"
    echo -e "  ${CYAN}--display=<true|false>${NC}          Set WP_DEBUG_DISPLAY"
    echo -e "  ${CYAN}--script-debug=<true|false>${NC}     Set SCRIPT_DEBUG"
    echo -e "  ${CYAN}--savequeries=<true|false>${NC}      Set SAVEQUERIES"
    echo
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  ${CYAN}shellbe wpd${NC}                     Interactive mode"
    echo -e "  ${CYAN}shellbe wpd myserver${NC}            Manage WordPress on myserver"
    echo -e "  ${CYAN}shellbe wpd myserver find${NC}       Find WordPress installations on myserver"
    echo -e "  ${CYAN}shellbe wpd myserver status${NC}     Check debugging status on myserver"
}

# Interactive mode - Select server
select_server() {
    echo -e "${BLUE}Select a server:${NC}"
    
    # Get list of servers from shellbe
    local servers=$(get_shellbe_profiles)
    
    if [ -z "$servers" ]; then
        echo -e "${RED}No servers found. Please add a server profile first with 'shellbe add'${NC}"
        return 1
    fi
    
    # Display numbered list of servers
    local i=1
    local server_array=()
    while IFS= read -r server; do
        if [ -n "$server" ]; then  # Skip empty lines
            server_array+=("$server")
            echo -e "${CYAN}$i)${NC} $server"
            i=$((i + 1))
        fi
    done <<< "$servers"
    
    # Add option to exit
    echo -e "${CYAN}$i)${NC} Exit"
    
    # Get user selection
    local selection
    read -p "Enter selection number: " selection
    
    # Validate selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$i" ]; then
        echo -e "${RED}Invalid selection${NC}"
        return 1
    fi
    
    # Exit if selected
    if [ "$selection" -eq "$i" ]; then
        return 1
    fi
    
    # Return selected server
    echo "${server_array[$((selection - 1))]}"
}

# Interactive mode - Select action for a server
select_action() {
    local profile="$1"
    
    # Validate input
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}WordPress actions for server: ${CYAN}$profile${NC}"
    
    # Display actions
    echo -e "${CYAN}1)${NC} Find WordPress installations"
    echo -e "${CYAN}2)${NC} List WordPress installations"
    echo -e "${CYAN}3)${NC} Check debugging status"
    echo -e "${CYAN}4)${NC} Enable debugging"
    echo -e "${CYAN}5)${NC} Disable debugging"
    echo -e "${CYAN}6)${NC} View debug log"
    echo -e "${CYAN}7)${NC} Configure debugging settings"
    echo -e "${CYAN}8)${NC} Set default WordPress installation"
    echo -e "${CYAN}9)${NC} Go back"
    
    # Get user selection
    local selection
    read -p "Enter selection number: " selection
    
    # Validate selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt 9 ]; then
        echo -e "${RED}Invalid selection${NC}"
        return 1
    fi
    
    # Execute selected action
    case "$selection" in
        1)
            find_wp_config "$profile"
            ;;
        2)
            list_wp_installations_interactive "$profile"
            ;;
        3)
            select_wp_installation "$profile" "status"
            ;;
        4)
            select_wp_installation "$profile" "enable"
            ;;
        5)
            select_wp_installation "$profile" "disable"
            ;;
        6)
            select_wp_installation "$profile" "log"
            ;;
        7)
            select_wp_installation "$profile" "configure"
            ;;
        8)
            select_wp_installation "$profile" "default"
            ;;
        9)
            return 1
            ;;
        *)
            echo -e "${RED}Invalid selection${NC}"
            return 1
            ;;
    esac
    
    # Show prompt to continue
    read -p "Press Enter to continue..."
    
    return 0
}

# Interactive mode - Select WordPress installation for a server
select_wp_installation() {
    local profile="$1"
    local action="$2"
    
    # Validate input
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified${NC}" >&2
        return 1
    fi
    
    # Get list of WordPress installations
    local installations=$(get_wp_installations "$profile")
    
    if [ -z "$installations" ]; then
        echo -e "${YELLOW}No WordPress installations found for server: $profile${NC}"
        echo -e "${YELLOW}Use 'find' command to discover WordPress installations.${NC}"
        
        read -p "Search for WordPress installations now? (y/n): " search_now
        if [[ "$search_now" == "y" || "$search_now" == "Y" ]]; then
            find_wp_config "$profile"
            # Re-get installations after search
            installations=$(get_wp_installations "$profile")
            if [ -z "$installations" ]; then
                echo -e "${RED}Still no WordPress installations found.${NC}"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    # Check for default installation
    local default_path=$(get_default_wp_installation "$profile")
    
    # If there's a default and only one action specified, use it
    if [ -n "$default_path" ] && [ -n "$action" ] && [ "$action" != "default" ]; then
        echo -e "${GREEN}Using default WordPress installation:${NC} $default_path"
        
        # Execute action with default installation
        case "$action" in
            "status")
                check_debug_status "$profile" "--path=$default_path"
                ;;
            "enable")
                enable_debugging "$profile" "--path=$default_path"
                ;;
            "disable")
                disable_debugging "$profile" "--path=$default_path"
                ;;
            "log")
                view_debug_log "$profile" "--path=$default_path"
                ;;
            "configure")
                configure_debugging "$profile" "--path=$default_path"
                ;;
            *)
                echo -e "${RED}Invalid action: $action${NC}"
                return 1
                ;;
        esac
        
        return 0
    fi
    
    # Display numbered list of installations
    echo -e "${BLUE}Select WordPress installation on server: ${CYAN}$profile${NC}"
    
    local i=1
    local wp_array=()
    while IFS= read -r wp_path; do
        if [ -n "$wp_path" ]; then  # Skip empty lines
            wp_array+=("$wp_path")
            local marker=" "
            if [ "$wp_path" = "$default_path" ]; then
                marker="*"
            fi
            echo -e "${CYAN}$i)${NC} $wp_path $marker"
            i=$((i + 1))
        fi
    done <<< "$installations"
    
    # Add option to go back
    echo -e "${CYAN}$i)${NC} Go back"
    
    # Get user selection
    local selection
    read -p "Enter selection number: " selection
    
    # Validate selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$i" ]; then
        echo -e "${RED}Invalid selection${NC}"
        return 1
    fi
    
    # Exit if selected
    if [ "$selection" -eq "$i" ]; then
        return 1
    fi
    
    # Get selected installation path
    local selected_path="${wp_array[$((selection - 1))]}"
    
    # If action is to set default, handle it separately
    if [ "$action" = "default" ]; then
        if save_default_wp_installation "$profile" "$selected_path"; then
            echo -e "${GREEN}Default WordPress installation set to:${NC} $selected_path"
        else
            echo -e "${RED}Failed to set default WordPress installation${NC}"
        fi
        return 0
    fi
    
    # Execute action with selected installation
    case "$action" in
        "status")
            check_debug_status "$profile" "--path=$selected_path"
            ;;
        "enable")
            enable_debugging "$profile" "--path=$selected_path"
            ;;
        "disable")
            disable_debugging "$profile" "--path=$selected_path"
            ;;
        "log")
            view_debug_log "$profile" "--path=$selected_path"
            ;;
        "configure")
            configure_debugging "$profile" "--path=$selected_path"
            ;;
        *)
            echo -e "${RED}Invalid action: $action${NC}"
            return 1
            ;;
    esac
    
    return 0
}

# List WordPress installations interactively
list_wp_installations_interactive() {
    local profile="$1"
    
    # Validate input
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified${NC}" >&2
        return 1
    fi
    
    # Get list of WordPress installations
    local installations=$(get_wp_installations "$profile")
    
    if [ -z "$installations" ]; then
        echo -e "${YELLOW}No WordPress installations found for server: $profile${NC}"
        echo -e "${YELLOW}Use 'find' command to discover WordPress installations.${NC}"
        
        read -p "Search for WordPress installations now? (y/n): " search_now
        if [[ "$search_now" == "y" || "$search_now" == "Y" ]]; then
            find_wp_config "$profile"
            # Re-get installations after search
            installations=$(get_wp_installations "$profile")
            if [ -z "$installations" ]; then
                echo -e "${RED}Still no WordPress installations found.${NC}"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    # Get default installation
    local default_path=$(get_default_wp_installation "$profile")
    
    # Display list of installations
    echo -e "${BLUE}WordPress installations on server: ${CYAN}$profile${NC}"
    echo -e "${YELLOW}-------------------------------------${NC}"
    
    local count=1
    while IFS= read -r wp_path; do
        if [ -n "$wp_path" ]; then  # Skip empty lines
            local marker=" "
            if [ "$wp_path" = "$default_path" ]; then
                marker="(Default)"
            fi
            
            # Get WordPress version
            local wp_version=$(get_wp_version "$profile" "$wp_path")
            
            # Check debugging status
            local debug_status=$(get_debug_setting "$profile" "$wp_path" "WP_DEBUG")
            local debug_indicator="Debugging: "
            
            if [ "$debug_status" = "true" ]; then
                debug_indicator="${debug_indicator}${GREEN}Enabled${NC}"
            else
                debug_indicator="${debug_indicator}${RED}Disabled${NC}"
            fi
            
            echo -e "${CYAN}$count)${NC} $wp_path ${YELLOW}$marker${NC}"
            echo -e "   WordPress: $wp_version, $debug_indicator"
            
            # Check if it's a production site
            if is_production_site "$profile" "$wp_path"; then
                echo -e "   ${RED}Production site detected!${NC}"
            fi
            
            count=$((count + 1))
        fi
    done <<< "$installations"
    echo -e "${YELLOW}-------------------------------------${NC}"
    
    return 0
}

# Find WordPress config files on a remote server
find_wp_config() {
    local profile="$1"
    shift
    
    # Validate input
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified${NC}" >&2
        return 1
    fi
    
    # Parse options
    local search_paths="$DEFAULT_SEARCH_PATHS"
    local search_depth="$MAX_SEARCH_DEPTH"
    local save_path=true  # Default to saving paths
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --search=*)
                search_paths="${1#*=}"
                ;;
            --depth=*)
                search_depth="${1#*=}"
                ;;
            --save-path)
                save_path=true
                ;;
            --no-save)
                save_path=false
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                return 1
                ;;
        esac
        shift
    done
    
    # Sanitize inputs for security
    search_paths=$(echo "$search_paths" | tr -d ';&|$()')
    
    # Ensure search_depth is a number
    if ! [[ "$search_depth" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid search depth: $search_depth. Using default: $MAX_SEARCH_DEPTH${NC}" >&2
        search_depth="$MAX_SEARCH_DEPTH"
    fi
    
    echo -e "${BLUE}Searching for WordPress configuration files on $profile...${NC}"
    echo -e "${YELLOW}This may take a while depending on the server size...${NC}"
    
    # Create a temporary script for the find operation
    local find_script="/tmp/wpd_find_wp_${RANDOM}.sh"
    cat > "$find_script" << EOF
#!/bin/bash
# Safe find command to locate WordPress configurations
find $search_paths -type f -name wp-config.php -maxdepth $search_depth 2>/dev/null
EOF
    chmod +x "$find_script"
    
    # Copy script to remote server
    local remote_script="/tmp/wpd_find_wp_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_script\"" < "$find_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_script\"" > /dev/null 2>&1
    
    # Execute the script on the remote server
    local results=$(shellbe_ssh_command "$profile" "bash \"$remote_script\"")
    local exit_code=$?
    
    # Clean up temporary files
    rm -f "$find_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_script\"" > /dev/null 2>&1
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}Error: Failed to search for WordPress installations${NC}" >&2
        return 1
    fi
    
    if [ -z "$results" ]; then
        echo -e "${RED}No WordPress configuration files found.${NC}"
        echo -e "${YELLOW}Try different search paths with --search option${NC}"
        return 1
    fi
    
    # Display results
    echo -e "${GREEN}WordPress configuration files found:${NC}"
    local count=1
    
    # Clear existing installations if found
    clear_wp_installations "$profile"
    
    while IFS= read -r path; do
        if [ -n "$path" ]; then  # Skip empty lines
            echo -e "${CYAN}$count)${NC} $path"
            
            # Save path
            if [ "$save_path" = true ]; then
                if save_wp_installation "$profile" "$path"; then
                    echo -e "   ${GREEN}✓ Saved${NC}"
                else
                    echo -e "   ${RED}✗ Failed to save${NC}"
                fi
            fi
            
            count=$((count + 1))
        fi
    done <<< "$results"
    
    echo -e "${GREEN}Found and saved ${CYAN}$((count - 1))${GREEN} WordPress installations for server: ${CYAN}$profile${NC}"
    
    # If this is the first installation, set it as default
    if [ "$count" -eq 2 ] && [ "$save_path" = true ]; then
        local first_path=$(echo "$results" | head -1)
        if save_default_wp_installation "$profile" "$first_path"; then
            echo -e "${GREEN}Set default WordPress installation to:${NC} $first_path"
        else
            echo -e "${RED}Failed to set default WordPress installation${NC}"
        fi
    elif [ "$count" -gt 2 ] && [ "$save_path" = true ]; then
        echo -e "${YELLOW}Multiple WordPress installations found.${NC}"
        echo -e "${YELLOW}Use 'shellbe wpd $profile default' to set your preferred default.${NC}"
    fi
    
    return 0
}

# Configure WordPress debugging settings
configure_debugging() {
    local profile="$1"
    shift
    
    # Validate input
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified${NC}" >&2
        return 1
    fi
    
    # Parse options and get WP config path
    local wp_config_path=""
    local custom_path=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path=*)
                custom_path="${1#*=}"
                ;;
            *)
                if [ -z "$wp_config_path" ] && [ -z "$custom_path" ]; then
                    wp_config_path="$1"
                else
                    echo -e "${RED}Unknown option: $1${NC}"
                    return 1
                fi
                ;;
        esac
        shift
    done
    
    # If path is not provided, try to get default path
    if [ -z "$custom_path" ] && [ -z "$wp_config_path" ]; then
        wp_config_path=$(get_default_wp_installation "$profile")
        
        if [ -z "$wp_config_path" ]; then
            echo -e "${RED}No WordPress configuration path provided or saved as default.${NC}"
            
            # Try to select from available installations
            select_wp_installation "$profile" "configure"
            return $?
        fi
    elif [ -n "$custom_path" ]; then
        wp_config_path="$custom_path"
    fi
    
    # Create a script to check if wp-config.php exists
    local check_script="/tmp/wpd_check_config_${RANDOM}.sh"
    cat > "$check_script" << EOF
#!/bin/bash
if [ -f "$wp_config_path" ]; then
    echo "exists"
else
    echo "not-exists"
fi
EOF
    chmod +x "$check_script"
    
    # Copy script to remote server
    local remote_check_script="/tmp/wpd_check_config_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_check_script\"" < "$check_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_check_script\"" > /dev/null 2>&1
    
    # Execute the script on the remote server
    local file_exists=$(shellbe_ssh_command "$profile" "bash \"$remote_check_script\"")
    
    # Clean up temporary files
    rm -f "$check_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_check_script\"" > /dev/null 2>&1
    
    if [ "$file_exists" != "exists" ]; then
        echo -e "${RED}Error: WordPress configuration file not found or not accessible at: $wp_config_path${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Configure WordPress debugging on $profile...${NC}"
    echo -e "${YELLOW}Path: $wp_config_path${NC}"
    
    # Get current settings
    local debug_status=$(get_debug_setting "$profile" "$wp_config_path" "WP_DEBUG")
    local debug_log=$(get_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG")
    local debug_display=$(get_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_DISPLAY")
    local script_debug=$(get_debug_setting "$profile" "$wp_config_path" "SCRIPT_DEBUG")
    local savequeries=$(get_debug_setting "$profile" "$wp_config_path" "SAVEQUERIES")
    
    # Display current settings
    echo -e "${BLUE}Current WordPress Debugging Settings:${NC}"
    echo -e "${YELLOW}-----------------------------------${NC}"
    
    if [ "$debug_status" = "true" ]; then
        echo -e "${CYAN}1)${NC} WP_DEBUG: ${GREEN}Enabled${NC}"
    else
        echo -e "${CYAN}1)${NC} WP_DEBUG: ${RED}Disabled${NC}"
    fi
    
    if [ "$debug_log" = "true" ]; then
        echo -e "${CYAN}2)${NC} WP_DEBUG_LOG: ${GREEN}Enabled${NC} (Default location)"
    elif [[ "$debug_log" =~ ^[\"\']/.*[\"\']$ ]]; then
        # For display purposes, strip the quotes
        local log_path="${debug_log:1:${#debug_log}-2}"
        echo -e "${CYAN}2)${NC} WP_DEBUG_LOG: ${GREEN}Enabled${NC} (Custom: $log_path)"
    else
        echo -e "${CYAN}2)${NC} WP_DEBUG_LOG: ${RED}Disabled${NC}"
    fi
    
    if [ "$debug_display" = "true" ]; then
        echo -e "${CYAN}3)${NC} WP_DEBUG_DISPLAY: ${GREEN}Enabled${NC} (Errors shown on screen)"
    else
        echo -e "${CYAN}3)${NC} WP_DEBUG_DISPLAY: ${RED}Disabled${NC} (Errors hidden from screen)"
    fi
    
    if [ "$script_debug" = "true" ]; then
        echo -e "${CYAN}4)${NC} SCRIPT_DEBUG: ${GREEN}Enabled${NC} (Non-minified scripts)"
    else
        echo -e "${CYAN}4)${NC} SCRIPT_DEBUG: ${RED}Disabled${NC} (Minified scripts)"
    fi
    
    if [ "$savequeries" = "true" ]; then
        echo -e "${CYAN}5)${NC} SAVEQUERIES: ${GREEN}Enabled${NC} (Save database queries)"
    else
        echo -e "${CYAN}5)${NC} SAVEQUERIES: ${RED}Disabled${NC} (Don't save database queries)"
    fi
    
    echo -e "${CYAN}6)${NC} Toggle all (quick debug mode)"
    echo -e "${CYAN}7)${NC} Production safe configuration"
    echo -e "${CYAN}8)${NC} Development configuration"
    echo -e "${CYAN}9)${NC} Cancel"
    echo -e "${YELLOW}-----------------------------------${NC}"
    
    # Get user selection
    local selection
    read -p "Enter setting to change (1-9): " selection
    
    # Validate selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt 9 ]; then
        echo -e "${RED}Invalid selection${NC}"
        return 1
    fi
    
    # Create backup if configured
    if [ "$BACKUP_BEFORE_CHANGES" = "true" ]; then
        if ! create_config_backup "$profile" "$wp_config_path"; then
            echo -e "${RED}Warning: Failed to create backup of wp-config.php${NC}" >&2
            read -p "Continue without backup? (y/n): " continue_without_backup
            if [[ "$continue_without_backup" != "y" && "$continue_without_backup" != "Y" ]]; then
                echo -e "${YELLOW}Configuration cancelled.${NC}"
                return 1
            fi
        fi
    fi
    
    # Execute selected action
    case "$selection" in
        1)
            # Toggle WP_DEBUG
            if [ "$debug_status" = "true" ]; then
                if set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG" "false"; then
                    echo -e "${GREEN}WP_DEBUG disabled${NC}"
                else
                    echo -e "${RED}Failed to disable WP_DEBUG${NC}"
                fi
            else
                if set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG" "true"; then
                    echo -e "${GREEN}WP_DEBUG enabled${NC}"
                else
                    echo -e "${RED}Failed to enable WP_DEBUG${NC}"
                fi
            fi
            ;;
        2)
            # Configure WP_DEBUG_LOG
            echo -e "${YELLOW}WP_DEBUG_LOG options:${NC}"
            echo -e "${CYAN}1)${NC} Enable (default location)"
            echo -e "${CYAN}2)${NC} Enable with custom path"
            echo -e "${CYAN}3)${NC} Disable"
            
            local log_selection
            read -p "Enter option (1-3): " log_selection
            
            case "$log_selection" in
                1)
                    if set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG" "true"; then
                        echo -e "${GREEN}WP_DEBUG_LOG enabled (default location)${NC}"
                    else
                        echo -e "${RED}Failed to enable WP_DEBUG_LOG${NC}"
                    fi
                    ;;
                2)
                    read -p "Enter custom log path (e.g. /home/user/wp-debug.log): " custom_log_path
                    # Sanitize the custom log path
                    custom_log_path=$(echo "$custom_log_path" | tr -d ';&|$()')
                    if set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG" "'$custom_log_path'"; then
                        echo -e "${GREEN}WP_DEBUG_LOG enabled (custom path: $custom_log_path)${NC}"
                    else
                        echo -e "${RED}Failed to enable WP_DEBUG_LOG with custom path${NC}"
                    fi
                    ;;
                3)
                    if set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG" "false"; then
                        echo -e "${GREEN}WP_DEBUG_LOG disabled${NC}"
                    else
                        echo -e "${RED}Failed to disable WP_DEBUG_LOG${NC}"
                    fi
                    ;;
                *)
                    echo -e "${RED}Invalid selection${NC}"
                    ;;
            esac
            ;;
        3)
            # Toggle WP_DEBUG_DISPLAY
            if [ "$debug_display" = "true" ]; then
                if set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_DISPLAY" "false"; then
                    echo -e "${GREEN}WP_DEBUG_DISPLAY disabled (errors hidden from screen)${NC}"
                else
                    echo -e "${RED}Failed to disable WP_DEBUG_DISPLAY${NC}"
                fi
            else
                if set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_DISPLAY" "true"; then
                    echo -e "${GREEN}WP_DEBUG_DISPLAY enabled (errors shown on screen)${NC}"
                else
                    echo -e "${RED}Failed to enable WP_DEBUG_DISPLAY${NC}"
                fi
            fi
            ;;
        4)
            # Toggle SCRIPT_DEBUG
            if [ "$script_debug" = "true" ]; then
                if set_debug_setting "$profile" "$wp_config_path" "SCRIPT_DEBUG" "false"; then
                    echo -e "${GREEN}SCRIPT_DEBUG disabled (minified scripts)${NC}"
                else
                    echo -e "${RED}Failed to disable SCRIPT_DEBUG${NC}"
                fi
            else
                if set_debug_setting "$profile" "$wp_config_path" "SCRIPT_DEBUG" "true"; then
                    echo -e "${GREEN}SCRIPT_DEBUG enabled (non-minified scripts)${NC}"
                else
                    echo -e "${RED}Failed to enable SCRIPT_DEBUG${NC}"
                fi
            fi
            ;;
        5)
            # Toggle SAVEQUERIES
            if [ "$savequeries" = "true" ]; then
                if set_debug_setting "$profile" "$wp_config_path" "SAVEQUERIES" "false"; then
                    echo -e "${GREEN}SAVEQUERIES disabled (don't save database queries)${NC}"
                else
                    echo -e "${RED}Failed to disable SAVEQUERIES${NC}"
                fi
            else
                if set_debug_setting "$profile" "$wp_config_path" "SAVEQUERIES" "true"; then
                    echo -e "${GREEN}SAVEQUERIES enabled (save database queries)${NC}"
                else
                    echo -e "${RED}Failed to enable SAVEQUERIES${NC}"
                fi
            fi
            ;;
        6)
            # Quick debug mode - Toggle all
            if [ "$debug_status" = "true" ]; then
                # Disable all debugging
                local success=true
                
                if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG" "false"; then
                    echo -e "${RED}Failed to disable WP_DEBUG${NC}" >&2
                    success=false
                fi
                if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG" "false"; then
                    echo -e "${RED}Failed to disable WP_DEBUG_LOG${NC}" >&2
                    success=false
                fi
                if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_DISPLAY" "false"; then
                    echo -e "${RED}Failed to disable WP_DEBUG_DISPLAY${NC}" >&2
                    success=false
                fi
                if ! set_debug_setting "$profile" "$wp_config_path" "SCRIPT_DEBUG" "false"; then
                    echo -e "${RED}Failed to disable SCRIPT_DEBUG${NC}" >&2
                    success=false
                fi
                if ! set_debug_setting "$profile" "$wp_config_path" "SAVEQUERIES" "false"; then
                    echo -e "${RED}Failed to disable SAVEQUERIES${NC}" >&2
                    success=false
                fi
                
                if [ "$success" = true ]; then
                    echo -e "${GREEN}All debugging options disabled${NC}"
                else
                    echo -e "${RED}Some debugging options could not be disabled${NC}"
                fi
            else
                # Enable all debugging
                local success=true
                
                if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG" "true"; then
                    echo -e "${RED}Failed to enable WP_DEBUG${NC}" >&2
                    success=false
                fi
                if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG" "true"; then
                    echo -e "${RED}Failed to enable WP_DEBUG_LOG${NC}" >&2
                    success=false
                fi
                if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_DISPLAY" "true"; then
                    echo -e "${RED}Failed to enable WP_DEBUG_DISPLAY${NC}" >&2
                    success=false
                fi
                if ! set_debug_setting "$profile" "$wp_config_path" "SCRIPT_DEBUG" "true"; then
                    echo -e "${RED}Failed to enable SCRIPT_DEBUG${NC}" >&2
                    success=false
                fi
                if ! set_debug_setting "$profile" "$wp_config_path" "SAVEQUERIES" "true"; then
                    echo -e "${RED}Failed to enable SAVEQUERIES${NC}" >&2
                    success=false
                fi
                
                if [ "$success" = true ]; then
                    echo -e "${GREEN}All debugging options enabled${NC}"
                else
                    echo -e "${RED}Some debugging options could not be enabled${NC}"
                fi
            fi
            ;;
        7)
            # Production safe configuration
            local success=true
            
            if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG" "true"; then
                echo -e "${RED}Failed to enable WP_DEBUG${NC}" >&2
                success=false
            fi
            if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG" "true"; then
                echo -e "${RED}Failed to enable WP_DEBUG_LOG${NC}" >&2
                success=false
            fi
            if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_DISPLAY" "false"; then
                echo -e "${RED}Failed to disable WP_DEBUG_DISPLAY${NC}" >&2
                success=false
            fi
            if ! set_debug_setting "$profile" "$wp_config_path" "SCRIPT_DEBUG" "false"; then
                echo -e "${RED}Failed to disable SCRIPT_DEBUG${NC}" >&2
                success=false
            fi
            if ! set_debug_setting "$profile" "$wp_config_path" "SAVEQUERIES" "false"; then
                echo -e "${RED}Failed to disable SAVEQUERIES${NC}" >&2
                success=false
            fi
            
            if [ "$success" = true ]; then
                echo -e "${GREEN}Production safe debugging configuration applied${NC}"
                echo -e "${YELLOW}Errors will be logged but not displayed on screen${NC}"
            else
                echo -e "${RED}Some configuration settings could not be applied${NC}"
            fi
            ;;
        8)
            # Development configuration
            local success=true
            
            if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG" "true"; then
                echo -e "${RED}Failed to enable WP_DEBUG${NC}" >&2
                success=false
            fi
            if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG" "true"; then
                echo -e "${RED}Failed to enable WP_DEBUG_LOG${NC}" >&2
                success=false
            fi
            if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_DISPLAY" "true"; then
                echo -e "${RED}Failed to enable WP_DEBUG_DISPLAY${NC}" >&2
                success=false
            fi
            if ! set_debug_setting "$profile" "$wp_config_path" "SCRIPT_DEBUG" "true"; then
                echo -e "${RED}Failed to enable SCRIPT_DEBUG${NC}" >&2
                success=false
            fi
            if ! set_debug_setting "$profile" "$wp_config_path" "SAVEQUERIES" "true"; then
                echo -e "${RED}Failed to enable SAVEQUERIES${NC}" >&2
                success=false
            fi
            
            if [ "$success" = true ]; then
                echo -e "${GREEN}Development debugging configuration applied${NC}"
                echo -e "${YELLOW}All debugging options enabled for maximum visibility${NC}"
            else
                echo -e "${RED}Some configuration settings could not be applied${NC}"
            fi
            ;;
        9)
            echo -e "${YELLOW}Configuration cancelled${NC}"
            ;;
        *)
            echo -e "${RED}Invalid selection${NC}"
            ;;
    esac
    
    return 0
}

# Check WordPress debugging status
check_debug_status() {
    local profile="$1"
    shift
    
    # Validate input
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified${NC}" >&2
        return 1
    fi
    
    # Parse options and get WP config path
    local wp_config_path=""
    local custom_path=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path=*)
                custom_path="${1#*=}"
                ;;
            *)
                if [ -z "$wp_config_path" ] && [ -z "$custom_path" ]; then
                    wp_config_path="$1"
                else
                    echo -e "${RED}Unknown option: $1${NC}"
                    return 1
                fi
                ;;
        esac
        shift
    done
    
    # If path is not provided, try to get default path
    if [ -z "$custom_path" ] && [ -z "$wp_config_path" ]; then
        wp_config_path=$(get_default_wp_installation "$profile")
        
        if [ -z "$wp_config_path" ]; then
            echo -e "${RED}No WordPress configuration path provided or saved as default.${NC}"
            
            # Try to select from available installations
            select_wp_installation "$profile" "status"
            return $?
        fi
    elif [ -n "$custom_path" ]; then
        wp_config_path="$custom_path"
    fi
    
    # Create a script to check if wp-config.php exists
    local check_script="/tmp/wpd_check_config_${RANDOM}.sh"
    cat > "$check_script" << EOF
#!/bin/bash
if [ -f "$wp_config_path" ]; then
    echo "exists"
else
    echo "not-exists"
fi
EOF
    chmod +x "$check_script"
    
    # Copy script to remote server
    local remote_check_script="/tmp/wpd_check_config_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_check_script\"" < "$check_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_check_script\"" > /dev/null 2>&1
    
    # Execute the script on the remote server
    local file_exists=$(shellbe_ssh_command "$profile" "bash \"$remote_check_script\"")
    
    # Clean up temporary files
    rm -f "$check_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_check_script\"" > /dev/null 2>&1
    
    if [ "$file_exists" != "exists" ]; then
        echo -e "${RED}Error: WordPress configuration file not found or not accessible at: $wp_config_path${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Checking WordPress debugging status on $profile...${NC}"
    echo -e "${YELLOW}Path: $wp_config_path${NC}"
    
    # Get debug settings
    local debug_status=$(get_debug_setting "$profile" "$wp_config_path" "WP_DEBUG")
    local debug_log=$(get_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG")
    local debug_display=$(get_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_DISPLAY")
    local script_debug=$(get_debug_setting "$profile" "$wp_config_path" "SCRIPT_DEBUG")
    local savequeries=$(get_debug_setting "$profile" "$wp_config_path" "SAVEQUERIES")
    
    # Display results
    echo -e "${BLUE}WordPress Debugging Status:${NC}"
    echo -e "${YELLOW}-----------------------------------${NC}"
    
    if [ "$debug_status" = "true" ]; then
        echo -e "${GREEN}WP_DEBUG:${NC} Enabled"
    else
        echo -e "${RED}WP_DEBUG:${NC} Disabled"
    fi
    
    if [ "$debug_log" = "true" ]; then
        echo -e "${GREEN}WP_DEBUG_LOG:${NC} Enabled"
        
        # Check if log file exists and get path
        local log_file=""
        
        if [[ "$debug_log" =~ ^[\"\']/.*[\"\']$ ]]; then
            # Custom log path - strip the quotes
            log_file="${debug_log:1:${#debug_log}-2}"
            echo -e "  Log file: $log_file"
        else
            # Default log path
            local wp_content_dir=$(dirname "$wp_config_path")/wp-content
            log_file="$wp_content_dir/debug.log"
            echo -e "  Log file: $log_file (default)"
        fi
        
        # Create a script to check log file
        local log_script="/tmp/wpd_check_log_${RANDOM}.sh"
        cat > "$log_script" << EOF
#!/bin/bash
if [ -f "$log_file" ]; then
  echo "exists"
  if [ -w "$log_file" ]; then
    echo "writable"
  else
    echo "not-writable"
  fi
  ls -lh "$log_file" 2>/dev/null | awk '{print \$5}' || echo 'unknown'
else
  echo "not-exists"
  echo "not-writable"
  echo "unknown"
fi
EOF
        chmod +x "$log_script"
        
        # Copy script to remote server
        local remote_log_script="/tmp/wpd_check_log_${RANDOM}.sh"
        shellbe_ssh_command "$profile" "cat > \"$remote_log_script\"" < "$log_script"
        shellbe_ssh_command "$profile" "chmod +x \"$remote_log_script\"" > /dev/null 2>&1
        
        # Execute the script on the remote server
        local log_info=$(shellbe_ssh_command "$profile" "bash \"$remote_log_script\"")
        
        # Clean up temporary files
        rm -f "$log_script"
        shellbe_ssh_command "$profile" "rm -f \"$remote_log_script\"" > /dev/null 2>&1
        
        # Parse results (line 1: exists/not-exists, line 2: writable/not-writable, line 3: size)
        local log_exists=$(echo "$log_info" | sed -n '1p')
        local log_writable=$(echo "$log_info" | sed -n '2p')
        local log_size=$(echo "$log_info" | sed -n '3p')
        
        if [ "$log_exists" = "exists" ]; then
            echo -e "  Status: ${GREEN}Exists${NC} (Size: $log_size)"
        else
            echo -e "  Status: ${RED}Does not exist${NC}"
        fi
        
        if [ "$log_writable" = "writable" ]; then
            echo -e "  Permissions: ${GREEN}Writable${NC}"
        else
            echo -e "  Permissions: ${RED}Not writable${NC}"
        fi
    elif [[ "$debug_log" =~ ^[\"\']/.*[\"\']$ ]]; then
        echo -e "${GREEN}WP_DEBUG_LOG:${NC} Enabled (Custom path)"
        # Strip quotes for display
        local log_file="${debug_log:1:${#debug_log}-2}"
        echo -e "  Log file: $log_file"
        
        # Create a script to check log file
        local log_script="/tmp/wpd_check_log_${RANDOM}.sh"
        cat > "$log_script" << EOF
#!/bin/bash
if [ -f "$log_file" ]; then
  echo "exists"
  if [ -w "$log_file" ]; then
    echo "writable"
  else
    echo "not-writable"
  fi
  ls -lh "$log_file" 2>/dev/null | awk '{print \$5}' || echo 'unknown'
else
  echo "not-exists"
  echo "not-writable"
  echo "unknown"
fi
EOF
        chmod +x "$log_script"
        
        # Copy script to remote server
        local remote_log_script="/tmp/wpd_check_log_${RANDOM}.sh"
        shellbe_ssh_command "$profile" "cat > \"$remote_log_script\"" < "$log_script"
        shellbe_ssh_command "$profile" "chmod +x \"$remote_log_script\"" > /dev/null 2>&1
        
        # Execute the script on the remote server
        local log_info=$(shellbe_ssh_command "$profile" "bash \"$remote_log_script\"")
        
        # Clean up temporary files
        rm -f "$log_script"
        shellbe_ssh_command "$profile" "rm -f \"$remote_log_script\"" > /dev/null 2>&1
        
        # Parse results (line 1: exists/not-exists, line 2: writable/not-writable, line 3: size)
        local log_exists=$(echo "$log_info" | sed -n '1p')
        local log_writable=$(echo "$log_info" | sed -n '2p')
        local log_size=$(echo "$log_info" | sed -n '3p')
        
        if [ "$log_exists" = "exists" ]; then
            echo -e "  Status: ${GREEN}Exists${NC} (Size: $log_size)"
        else
            echo -e "  Status: ${RED}Does not exist${NC}"
        fi
        
        if [ "$log_writable" = "writable" ]; then
            echo -e "  Permissions: ${GREEN}Writable${NC}"
        else
            echo -e "  Permissions: ${RED}Not writable${NC}"
        fi
    else
        echo -e "${RED}WP_DEBUG_LOG:${NC} Disabled"
    fi
    
    if [ "$debug_display" = "true" ]; then
        echo -e "${GREEN}WP_DEBUG_DISPLAY:${NC} Enabled (errors shown on screen)"
    else
        echo -e "${RED}WP_DEBUG_DISPLAY:${NC} Disabled (errors hidden from screen)"
    fi
    
    if [ "$script_debug" = "true" ]; then
        echo -e "${GREEN}SCRIPT_DEBUG:${NC} Enabled (non-minified scripts)"
    else
        echo -e "${RED}SCRIPT_DEBUG:${NC} Disabled (minified scripts)"
    fi
    
    if [ "$savequeries" = "true" ]; then
        echo -e "${GREEN}SAVEQUERIES:${NC} Enabled (saving database queries)"
    else
        echo -e "${RED}SAVEQUERIES:${NC} Disabled (not saving database queries)"
    fi
    
    # Display WordPress & PHP versions
    local wp_version=$(get_wp_version "$profile" "$wp_config_path")
    local php_version=$(get_php_version "$profile")
    
    echo -e "${YELLOW}-----------------------------------${NC}"
    echo -e "${BLUE}WordPress Version:${NC} $wp_version"
    echo -e "${BLUE}PHP Version:${NC} $php_version"
    
    # Check if it's a production site
    if is_production_site "$profile" "$wp_config_path"; then
        echo -e "${RED}WARNING: This appears to be a PRODUCTION site!${NC}"
        
        if [ "$debug_status" = "true" ]; then
            echo -e "${RED}Debugging is enabled on a production site. This is not recommended!${NC}"
            echo -e "${YELLOW}Consider using a production-safe configuration:${NC}"
            echo -e "  ${CYAN}shellbe wpd $profile configure${NC}"
        fi
    else
        echo -e "${GREEN}Environment: Development/Staging${NC}"
    fi
    
    return 0
}

# Enable WordPress debugging
enable_debugging() {
    local profile="$1"
    shift
    
    # Validate input
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified${NC}" >&2
        return 1
    fi
    
    # Parse options and get WP config path
    local wp_config_path=""
    local custom_path=""
    local save_path=false
    local debug_log_path=""
    local debug_display="false"  # Default to hiding errors on screen (safer)
    local script_debug="true"    # Default to enabling script debug
    local savequeries="false"    # Default to disabling query saving
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path=*)
                custom_path="${1#*=}"
                ;;
            --save-path)
                save_path=true
                ;;
            --debug-log=*)
                debug_log_path="${1#*=}"
                ;;
            --display=*)
                debug_display="${1#*=}"
                ;;
            --script-debug=*)
                script_debug="${1#*=}"
                ;;
            --savequeries=*)
                savequeries="${1#*=}"
                ;;
            *)
                if [ -z "$wp_config_path" ] && [ -z "$custom_path" ]; then
                    wp_config_path="$1"
                else
                    echo -e "${RED}Unknown option: $1${NC}"
                    return 1
                fi
                ;;
        esac
        shift
    done
    
    # If path is not provided, try to get default path
    if [ -z "$custom_path" ] && [ -z "$wp_config_path" ]; then
        wp_config_path=$(get_default_wp_installation "$profile")
        
        if [ -z "$wp_config_path" ]; then
            echo -e "${RED}No WordPress configuration path provided or saved as default.${NC}"
            
            # Try to select from available installations
            select_wp_installation "$profile" "enable"
            return $?
        fi
    elif [ -n "$custom_path" ]; then
        wp_config_path="$custom_path"
        
        if [ "$save_path" = true ]; then
            if save_wp_installation "$profile" "$wp_config_path"; then
                echo -e "${GREEN}Path saved for future use with profile '$profile'.${NC}"
            else
                echo -e "${RED}Failed to save path for future use${NC}" >&2
            fi
        fi
    fi
    
    # Create a script to check if wp-config.php exists
    local check_script="/tmp/wpd_check_config_${RANDOM}.sh"
    cat > "$check_script" << EOF
#!/bin/bash
if [ -f "$wp_config_path" ]; then
    echo "exists"
else
    echo "not-exists"
fi
EOF
    chmod +x "$check_script"
    
    # Copy script to remote server
    local remote_check_script="/tmp/wpd_check_config_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_check_script\"" < "$check_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_check_script\"" > /dev/null 2>&1
    
    # Execute the script on the remote server
    local file_exists=$(shellbe_ssh_command "$profile" "bash \"$remote_check_script\"")
    
    # Clean up temporary files
    rm -f "$check_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_check_script\"" > /dev/null 2>&1
    
    if [ "$file_exists" != "exists" ]; then
        echo -e "${RED}Error: WordPress configuration file not found or not accessible at: $wp_config_path${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Enabling WordPress debugging on $profile...${NC}"
    echo -e "${YELLOW}Path: $wp_config_path${NC}"
    
    # Check if it's a production site
    if is_production_site "$profile" "$wp_config_path"; then
        echo -e "${RED}WARNING: This appears to be a PRODUCTION site!${NC}"
        read -p "Are you sure you want to enable debugging on a production site? (y/n): " confirm
        
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "${YELLOW}Debugging not enabled. Consider a production-safe configuration instead.${NC}"
            return 0
        fi
        
        # For production sites, recommend safer defaults
        if [ "$debug_display" = "true" ]; then
            echo -e "${YELLOW}Showing errors on screen in production is not recommended.${NC}"
            read -p "Disable on-screen errors for safety? (y/n): " hide_errors
            
            if [[ "$hide_errors" == "y" || "$hide_errors" == "Y" ]]; then
                debug_display="false"
            fi
        fi
    fi
    
    # Create backup if configured
    if [ "$BACKUP_BEFORE_CHANGES" = "true" ]; then
        if ! create_config_backup "$profile" "$wp_config_path"; then
            echo -e "${RED}Warning: Failed to create backup of wp-config.php${NC}" >&2
            read -p "Continue without backup? (y/n): " continue_without_backup
            if [[ "$continue_without_backup" != "y" && "$continue_without_backup" != "Y" ]]; then
                echo -e "${YELLOW}Debugging not enabled.${NC}"
                return 1
            fi
        fi
    fi
    
    # Enable debugging
    local success=true
    
    if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG" "true"; then
        echo -e "${RED}Failed to enable WP_DEBUG${NC}" >&2
        success=false
    fi
    
    # Configure debug log
    if [ -n "$debug_log_path" ]; then
        # Sanitize the debug log path
        debug_log_path=$(echo "$debug_log_path" | tr -d ';&|$()')
        if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG" "'$debug_log_path'"; then
            echo -e "${RED}Failed to set WP_DEBUG_LOG to custom path${NC}" >&2
            success=false
        fi
    else
        if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG" "true"; then
            echo -e "${RED}Failed to enable WP_DEBUG_LOG${NC}" >&2
            success=false
        fi
    fi
    
    # Configure debug display
    if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_DISPLAY" "$debug_display"; then
        echo -e "${RED}Failed to set WP_DEBUG_DISPLAY${NC}" >&2
        success=false
    fi
    
    # Configure script debug
    if ! set_debug_setting "$profile" "$wp_config_path" "SCRIPT_DEBUG" "$script_debug"; then
        echo -e "${RED}Failed to set SCRIPT_DEBUG${NC}" >&2
        success=false
    fi
    
    # Configure save queries
    if ! set_debug_setting "$profile" "$wp_config_path" "SAVEQUERIES" "$savequeries"; then
        echo -e "${RED}Failed to set SAVEQUERIES${NC}" >&2
        success=false
    fi
    
    if [ "$success" = true ]; then
        echo -e "${GREEN}WordPress debugging enabled successfully!${NC}"
        echo -e "${YELLOW}Configuration applied:${NC}"
        echo -e "  WP_DEBUG: true"
        if [ -n "$debug_log_path" ]; then
            echo -e "  WP_DEBUG_LOG: '$debug_log_path'"
        else
            echo -e "  WP_DEBUG_LOG: true"
        fi
        echo -e "  WP_DEBUG_DISPLAY: $debug_display"
        echo -e "  SCRIPT_DEBUG: $script_debug"
        echo -e "  SAVEQUERIES: $savequeries"
        
        echo -e "${YELLOW}You can check the status with:${NC}"
        echo -e "  ${CYAN}shellbe wpd $profile status${NC}"
    else
        echo -e "${RED}Some debugging options could not be enabled${NC}"
    fi
    
    return 0
}

# Disable WordPress debugging
disable_debugging() {
    local profile="$1"
    shift
    
    # Validate input
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified${NC}" >&2
        return 1
    fi
    
    # Parse options and get WP config path
    local wp_config_path=""
    local custom_path=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path=*)
                custom_path="${1#*=}"
                ;;
            *)
                if [ -z "$wp_config_path" ] && [ -z "$custom_path" ]; then
                    wp_config_path="$1"
                else
                    echo -e "${RED}Unknown option: $1${NC}"
                    return 1
                fi
                ;;
        esac
        shift
    done
    
    # If path is not provided, try to get default path
    if [ -z "$custom_path" ] && [ -z "$wp_config_path" ]; then
        wp_config_path=$(get_default_wp_installation "$profile")
        
        if [ -z "$wp_config_path" ]; then
            echo -e "${RED}No WordPress configuration path provided or saved as default.${NC}"
            
            # Try to select from available installations
            select_wp_installation "$profile" "disable"
            return $?
        fi
    elif [ -n "$custom_path" ]; then
        wp_config_path="$custom_path"
    fi
    
    # Create a script to check if wp-config.php exists
    local check_script="/tmp/wpd_check_config_${RANDOM}.sh"
    cat > "$check_script" << EOF
#!/bin/bash
if [ -f "$wp_config_path" ]; then
    echo "exists"
else
    echo "not-exists"
fi
EOF
    chmod +x "$check_script"
    
    # Copy script to remote server
    local remote_check_script="/tmp/wpd_check_config_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_check_script\"" < "$check_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_check_script\"" > /dev/null 2>&1
    
    # Execute the script on the remote server
    local file_exists=$(shellbe_ssh_command "$profile" "bash \"$remote_check_script\"")
    
    # Clean up temporary files
    rm -f "$check_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_check_script\"" > /dev/null 2>&1
    
    if [ "$file_exists" != "exists" ]; then
        echo -e "${RED}Error: WordPress configuration file not found or not accessible at: $wp_config_path${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Disabling WordPress debugging on $profile...${NC}"
    echo -e "${YELLOW}Path: $wp_config_path${NC}"
    
    # Create backup if configured
    if [ "$BACKUP_BEFORE_CHANGES" = "true" ]; then
        if ! create_config_backup "$profile" "$wp_config_path"; then
            echo -e "${RED}Warning: Failed to create backup of wp-config.php${NC}" >&2
            read -p "Continue without backup? (y/n): " continue_without_backup
            if [[ "$continue_without_backup" != "y" && "$continue_without_backup" != "Y" ]]; then
                echo -e "${YELLOW}Debugging not disabled.${NC}"
                return 1
            fi
        fi
    fi
    
    # Disable debugging
    local success=true
    
    if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG" "false"; then
        echo -e "${RED}Failed to disable WP_DEBUG${NC}" >&2
        success=false
    fi
    
    if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG" "false"; then
        echo -e "${RED}Failed to disable WP_DEBUG_LOG${NC}" >&2
        success=false
    fi
    
    if ! set_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_DISPLAY" "false"; then
        echo -e "${RED}Failed to disable WP_DEBUG_DISPLAY${NC}" >&2
        success=false
    fi
    
    if ! set_debug_setting "$profile" "$wp_config_path" "SCRIPT_DEBUG" "false"; then
        echo -e "${RED}Failed to disable SCRIPT_DEBUG${NC}" >&2
        success=false
    fi
    
    if ! set_debug_setting "$profile" "$wp_config_path" "SAVEQUERIES" "false"; then
        echo -e "${RED}Failed to disable SAVEQUERIES${NC}" >&2
        success=false
    fi
    
    if [ "$success" = true ]; then
        echo -e "${GREEN}WordPress debugging disabled successfully!${NC}"
        echo -e "${YELLOW}You can verify with:${NC}"
        echo -e "  ${CYAN}shellbe wpd $profile status${NC}"
    else
        echo -e "${RED}Some debugging options could not be disabled${NC}"
    fi
    
    return 0
}

# View WordPress debug log
view_debug_log() {
    local profile="$1"
    shift
    
    # Validate input
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified${NC}" >&2
        return 1
    fi
    
    # Parse options and get WP config path
    local wp_config_path=""
    local custom_path=""
    local custom_log_path=""
    local log_limit="$DEBUG_LOG_LIMIT"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path=*)
                custom_path="${1#*=}"
                ;;
            --debug-log=*)
                custom_log_path="${1#*=}"
                ;;
            --limit=*)
                log_limit="${1#*=}"
                ;;
            *)
                if [ -z "$wp_config_path" ] && [ -z "$custom_path" ]; then
                    wp_config_path="$1"
                else
                    echo -e "${RED}Unknown option: $1${NC}"
                    return 1
                fi
                ;;
        esac
        shift
    done
    
    # Validate log_limit is a number
    if ! [[ "$log_limit" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid log limit: $log_limit. Using default: $DEBUG_LOG_LIMIT${NC}" >&2
        log_limit="$DEBUG_LOG_LIMIT"
    fi
    
    # If path is not provided and no custom log path, try to get default path
    if [ -z "$custom_path" ] && [ -z "$wp_config_path" ] && [ -z "$custom_log_path" ]; then
        wp_config_path=$(get_default_wp_installation "$profile")
        
        if [ -z "$wp_config_path" ]; then
            echo -e "${RED}No WordPress configuration path provided or saved as default.${NC}"
            
            # Try to select from available installations
            select_wp_installation "$profile" "log"
            return $?
        fi
    elif [ -n "$custom_path" ]; then
        wp_config_path="$custom_path"
    fi
    
    # Determine log file path
    local log_file=""
    
    if [ -n "$custom_log_path" ]; then
        # Sanitize the custom log path
        log_file=$(echo "$custom_log_path" | tr -d ';&|$()')
    elif [ -n "$wp_config_path" ]; then
        # Create a script to check if wp-config.php exists
        local check_script="/tmp/wpd_check_config_${RANDOM}.sh"
        cat > "$check_script" << EOF
#!/bin/bash
if [ -f "$wp_config_path" ]; then
    echo "exists"
else
    echo "not-exists"
fi
EOF
        chmod +x "$check_script"
        
        # Copy script to remote server
        local remote_check_script="/tmp/wpd_check_config_${RANDOM}.sh"
        shellbe_ssh_command "$profile" "cat > \"$remote_check_script\"" < "$check_script"
        shellbe_ssh_command "$profile" "chmod +x \"$remote_check_script\"" > /dev/null 2>&1
        
        # Execute the script on the remote server
        local file_exists=$(shellbe_ssh_command "$profile" "bash \"$remote_check_script\"")
        
        # Clean up temporary files
        rm -f "$check_script"
        shellbe_ssh_command "$profile" "rm -f \"$remote_check_script\"" > /dev/null 2>&1
        
        if [ "$file_exists" != "exists" ]; then
            echo -e "${RED}Error: WordPress configuration file not found or not accessible at: $wp_config_path${NC}" >&2
            return 1
        fi
        
        # Try to find log file path from wp-config.php
        local debug_log=$(get_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG")
        
        if [[ "$debug_log" =~ ^[\"\']/.*[\"\']$ ]]; then
            # Custom log path in config - strip the quotes
            log_file="${debug_log:1:${#debug_log}-2}"
        else
            # Default log path
            local wp_content_dir=$(dirname "$wp_config_path")/wp-content
            log_file="$wp_content_dir/debug.log"
        fi
    else
        echo -e "${RED}Error: No log file path specified${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Viewing WordPress debug log on $profile...${NC}"
    echo -e "${YELLOW}Log file: $log_file${NC}"
    
    # Create a script to check if log file exists
    local log_exists_script="/tmp/wpd_check_log_${RANDOM}.sh"
    cat > "$log_exists_script" << EOF
#!/bin/bash
if [ -f "$log_file" ]; then
    echo "exists"
else
    echo "not-exists"
fi
EOF
    chmod +x "$log_exists_script"
    
    # Copy script to remote server
    local remote_log_exists_script="/tmp/wpd_check_log_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_log_exists_script\"" < "$log_exists_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_log_exists_script\"" > /dev/null 2>&1
    
    # Execute the script on the remote server
    local log_exists=$(shellbe_ssh_command "$profile" "bash \"$remote_log_exists_script\"")
    
    # Clean up temporary files
    rm -f "$log_exists_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_log_exists_script\"" > /dev/null 2>&1
    
    if [ "$log_exists" != "exists" ]; then
        echo -e "${RED}Log file does not exist.${NC}"
        echo -e "${YELLOW}Make sure debugging is enabled and the log path is correct.${NC}"
        return 1
    fi
    
    # Create a script to get log file size and line count
    local log_info_script="/tmp/wpd_log_info_${RANDOM}.sh"
    cat > "$log_info_script" << EOF
#!/bin/bash
size=\$(ls -lh "$log_file" 2>/dev/null | awk '{print \$5}')
echo "\$size"
wc -l "$log_file" 2>/dev/null | awk '{print \$1}'
EOF
    chmod +x "$log_info_script"
    
    # Copy script to remote server
    local remote_log_info_script="/tmp/wpd_log_info_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_log_info_script\"" < "$log_info_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_log_info_script\"" > /dev/null 2>&1
    
    # Execute the script on the remote server
    local log_info=$(shellbe_ssh_command "$profile" "bash \"$remote_log_info_script\"")
    
    # Clean up temporary files
    rm -f "$log_info_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_log_info_script\"" > /dev/null 2>&1
    
    # Parse results (line 1: size, line 2: line count)
    local log_size=$(echo "$log_info" | sed -n '1p')
    local log_lines=$(echo "$log_info" | sed -n '2p')
    
    # Default values if parsing fails
    if [ -z "$log_size" ]; then log_size="unknown"; fi
    if [ -z "$log_lines" ] || ! [[ "$log_lines" =~ ^[0-9]+$ ]]; then log_lines="unknown"; fi
    
    echo -e "${BLUE}Log file size: $log_size, Lines: $log_lines${NC}"
    
    # Options for viewing log
    echo -e "${YELLOW}How would you like to view the log?${NC}"
    echo -e "${CYAN}1)${NC} View last $log_limit lines"
    echo -e "${CYAN}2)${NC} View first $log_limit lines"
    echo -e "${CYAN}3)${NC} View specific error types"
    echo -e "${CYAN}4)${NC} Clear log file"
    echo -e "${CYAN}5)${NC} Cancel"
    
    local log_option
    read -p "Enter option (1-5): " log_option
    
    # Validate input
    if [[ ! "$log_option" =~ ^[0-9]+$ ]] || [ "$log_option" -lt 1 ] || [ "$log_option" -gt 5 ]; then
        echo -e "${RED}Invalid option${NC}"
        return 1
    fi
    
    case "$log_option" in
        1)
            echo -e "${YELLOW}Displaying last $log_limit lines:${NC}"
            echo -e "${YELLOW}-----------------------------------${NC}"
            # Create a script to view the last lines of the log
            local tail_script="/tmp/wpd_tail_log_${RANDOM}.sh"
            cat > "$tail_script" << EOF
#!/bin/bash
tail -n $log_limit "$log_file"
EOF
            chmod +x "$tail_script"
            
            # Copy script to remote server
            local remote_tail_script="/tmp/wpd_tail_log_${RANDOM}.sh"
            shellbe_ssh_command "$profile" "cat > \"$remote_tail_script\"" < "$tail_script"
            shellbe_ssh_command "$profile" "chmod +x \"$remote_tail_script\"" > /dev/null 2>&1
            
            # Execute the script on the remote server
            shellbe_ssh_command "$profile" "bash \"$remote_tail_script\""
            
            # Clean up temporary files
            rm -f "$tail_script"
            shellbe_ssh_command "$profile" "rm -f \"$remote_tail_script\"" > /dev/null 2>&1
            
            echo -e "${YELLOW}-----------------------------------${NC}"
            ;;
        2)
            echo -e "${YELLOW}Displaying first $log_limit lines:${NC}"
            echo -e "${YELLOW}-----------------------------------${NC}"
            # Create a script to view the first lines of the log
            local head_script="/tmp/wpd_head_log_${RANDOM}.sh"
            cat > "$head_script" << EOF
#!/bin/bash
head -n $log_limit "$log_file"
EOF
            chmod +x "$head_script"
            
            # Copy script to remote server
            local remote_head_script="/tmp/wpd_head_log_${RANDOM}.sh"
            shellbe_ssh_command "$profile" "cat > \"$remote_head_script\"" < "$head_script"
            shellbe_ssh_command "$profile" "chmod +x \"$remote_head_script\"" > /dev/null 2>&1
            
            # Execute the script on the remote server
            shellbe_ssh_command "$profile" "bash \"$remote_head_script\""
            
            # Clean up temporary files
            rm -f "$head_script"
            shellbe_ssh_command "$profile" "rm -f \"$remote_head_script\"" > /dev/null 2>&1
            
            echo -e "${YELLOW}-----------------------------------${NC}"
            ;;
        3)
            echo -e "${YELLOW}Select error type to display:${NC}"
            echo -e "${CYAN}1)${NC} Fatal errors"
            echo -e "${CYAN}2)${NC} Warnings"
            echo -e "${CYAN}3)${NC} Notices"
            echo -e "${CYAN}4)${NC} Deprecated"
            echo -e "${CYAN}5)${NC} All errors (summary)"
            
            local error_option
            read -p "Enter option (1-5): " error_option
            
            # Validate input
            if [[ ! "$error_option" =~ ^[0-9]+$ ]] || [ "$error_option" -lt 1 ] || [ "$error_option" -gt 5 ]; then
                echo -e "${RED}Invalid option${NC}"
                return 1
            fi
            
            local grep_pattern=""
            case "$error_option" in
                1)
                    grep_pattern="Fatal error"
                    echo -e "${YELLOW}Displaying Fatal errors:${NC}"
                    ;;
                2)
                    grep_pattern="Warning"
                    echo -e "${YELLOW}Displaying Warnings:${NC}"
                    ;;
                3)
                    grep_pattern="Notice"
                    echo -e "${YELLOW}Displaying Notices:${NC}"
                    ;;
                4)
                    grep_pattern="Deprecated"
                    echo -e "${YELLOW}Displaying Deprecated:${NC}"
                    ;;
                5)
                    echo -e "${YELLOW}Error Summary:${NC}"
                    
                    # Create a script to summarize error types
                    local summary_script="/tmp/wpd_err_summary_${RANDOM}.sh"
                    cat > "$summary_script" << EOF
#!/bin/bash
grep -E 'PHP (Fatal|Parse|Warning|Notice|Deprecated)' "$log_file" | sort | uniq -c | sort -nr
EOF
                    chmod +x "$summary_script"
                    
                    # Copy script to remote server
                    local remote_summary_script="/tmp/wpd_err_summary_${RANDOM}.sh"
                    shellbe_ssh_command "$profile" "cat > \"$remote_summary_script\"" < "$summary_script"
                    shellbe_ssh_command "$profile" "chmod +x \"$remote_summary_script\"" > /dev/null 2>&1
                    
                    # Execute the script on the remote server
                    shellbe_ssh_command "$profile" "bash \"$remote_summary_script\""
                    
                    # Clean up temporary files
                    rm -f "$summary_script"
                    shellbe_ssh_command "$profile" "rm -f \"$remote_summary_script\"" > /dev/null 2>&1
                    
                    return 0
                    ;;
                *)
                    echo -e "${RED}Invalid option${NC}"
                    return 1
                    ;;
            esac
            
            echo -e "${YELLOW}-----------------------------------${NC}"
            
            # Create a script to filter log by error type
            local grep_script="/tmp/wpd_grep_log_${RANDOM}.sh"
            cat > "$grep_script" << EOF
#!/bin/bash
grep "$grep_pattern" "$log_file" | tail -n $log_limit
EOF
            chmod +x "$grep_script"
            
            # Copy script to remote server
            local remote_grep_script="/tmp/wpd_grep_log_${RANDOM}.sh"
            shellbe_ssh_command "$profile" "cat > \"$remote_grep_script\"" < "$grep_script"
            shellbe_ssh_command "$profile" "chmod +x \"$remote_grep_script\"" > /dev/null 2>&1
            
            # Execute the script on the remote server
            shellbe_ssh_command "$profile" "bash \"$remote_grep_script\""
            
            # Clean up temporary files
            rm -f "$grep_script"
            shellbe_ssh_command "$profile" "rm -f \"$remote_grep_script\"" > /dev/null 2>&1
            
            echo -e "${YELLOW}-----------------------------------${NC}"
            ;;
        4)
            read -p "Are you sure you want to clear the log file? (y/n): " confirm_clear
            if [[ "$confirm_clear" == "y" || "$confirm_clear" == "Y" ]]; then
                # Create a script to clear the log file
                local clear_script="/tmp/wpd_clear_log_${RANDOM}.sh"
                cat > "$clear_script" << EOF
#!/bin/bash
> "$log_file"
if [ \$? -eq 0 ]; then
    echo "success"
else
    echo "failure"
fi
EOF
                chmod +x "$clear_script"
                
                # Copy script to remote server
                local remote_clear_script="/tmp/wpd_clear_log_${RANDOM}.sh"
                shellbe_ssh_command "$profile" "cat > \"$remote_clear_script\"" < "$clear_script"
                shellbe_ssh_command "$profile" "chmod +x \"$remote_clear_script\"" > /dev/null 2>&1
                
                # Execute the script on the remote server
                local clear_result=$(shellbe_ssh_command "$profile" "bash \"$remote_clear_script\"")
                
                # Clean up temporary files
                rm -f "$clear_script"
                shellbe_ssh_command "$profile" "rm -f \"$remote_clear_script\"" > /dev/null 2>&1
                
                if [ "$clear_result" = "success" ]; then
                    echo -e "${GREEN}Log file cleared.${NC}"
                else
                    echo -e "${RED}Failed to clear log file. Check permissions.${NC}"
                fi
            else
                echo -e "${YELLOW}Log file not cleared.${NC}"
            fi
            ;;
        5)
            echo -e "${YELLOW}Operation cancelled.${NC}"
            return 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return 1
            ;;
    esac
    
    return 0
}

# Configure plugin settings
configure_plugin() {
    echo -e "${BLUE}WordPress Debug Plugin Configuration${NC}"
    echo -e "${YELLOW}Current settings:${NC}"
    echo -e "  1) Default search paths: ${CYAN}$DEFAULT_SEARCH_PATHS${NC}"
    echo -e "  2) Maximum search depth: ${CYAN}$MAX_SEARCH_DEPTH${NC}"
    echo -e "  3) Backup before changes: ${CYAN}$BACKUP_BEFORE_CHANGES${NC}"
    echo -e "  4) Debug log limit: ${CYAN}$DEBUG_LOG_LIMIT${NC}"
    echo -e "  5) Reset all saved WordPress paths"
    echo -e "  6) Back"
    echo
    
    read -p "Enter option number to change (1-6): " option
    
    # Validate input
    if [[ ! "$option" =~ ^[0-9]+$ ]] || [ "$option" -lt 1 ] || [ "$option" -gt 6 ]; then
        echo -e "${RED}Invalid option${NC}"
        configure_plugin  # Recursive call
        return 0
    fi
    
    case "$option" in
        1)
            read -p "Enter new default search paths (comma-separated): " new_paths
            # Sanitize paths for security
            new_paths=$(echo "$new_paths" | tr -d ';&|$()')
            if sed -i "s|^default_search_paths=.*|default_search_paths=$new_paths|" "$CONFIG_FILE"; then
                echo -e "${GREEN}Default search paths updated.${NC}"
                # Reload configuration
                DEFAULT_SEARCH_PATHS=$(grep "^default_search_paths=" "$CONFIG_FILE" | cut -d= -f2)
            else
                echo -e "${RED}Failed to update default search paths${NC}"
            fi
            ;;
        2)
            read -p "Enter new maximum search depth: " new_depth
            # Validate depth is a number
            if ! [[ "$new_depth" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Invalid depth value. Must be a positive number.${NC}"
            elif sed -i "s/^max_search_depth=.*/max_search_depth=$new_depth/" "$CONFIG_FILE"; then
                echo -e "${GREEN}Maximum search depth updated.${NC}"
                # Reload configuration
                MAX_SEARCH_DEPTH=$(grep "^max_search_depth=" "$CONFIG_FILE" | cut -d= -f2)
            else
                echo -e "${RED}Failed to update maximum search depth${NC}"
            fi
            ;;
        3)
            read -p "Backup before changes? (true/false): " new_backup
            # Validate backup is true or false
            if [ "$new_backup" != "true" ] && [ "$new_backup" != "false" ]; then
                echo -e "${RED}Invalid value. Must be 'true' or 'false'.${NC}"
            elif sed -i "s/^backup_before_changes=.*/backup_before_changes=$new_backup/" "$CONFIG_FILE"; then
                echo -e "${GREEN}Backup setting updated.${NC}"
                # Reload configuration
                BACKUP_BEFORE_CHANGES=$(grep "^backup_before_changes=" "$CONFIG_FILE" | cut -d= -f2)
            else
                echo -e "${RED}Failed to update backup setting${NC}"
            fi
            ;;
        4)
            read -p "Enter new debug log limit: " new_limit
            # Validate limit is a number
            if ! [[ "$new_limit" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Invalid limit value. Must be a positive number.${NC}"
            elif sed -i "s/^debug_log_limit=.*/debug_log_limit=$new_limit/" "$CONFIG_FILE"; then
                echo -e "${GREEN}Debug log limit updated.${NC}"
                # Reload configuration
                DEBUG_LOG_LIMIT=$(grep "^debug_log_limit=" "$CONFIG_FILE" | cut -d= -f2)
            else
                echo -e "${RED}Failed to update debug log limit${NC}"
            fi
            ;;
        5)
            read -p "Are you sure you want to reset all saved WordPress paths? (y/n): " confirm_reset
            if [[ "$confirm_reset" == "y" || "$confirm_reset" == "Y" ]]; then
                # Backup the files first
                backup_dir="$PLUGIN_DIR/backup_$(date +%Y%m%d%H%M%S)"
                mkdir -p "$backup_dir" || {
                    echo -e "${RED}Error: Failed to create backup directory${NC}" >&2
                    configure_plugin  # Recursive call
                    return 0
                }
                
                if [ -f "$WP_PATHS_FILE" ]; then
                    cp "$WP_PATHS_FILE" "$backup_dir/wp_paths.ini.backup.$(date '+%Y%m%d%H%M%S')" || {
                        echo -e "${YELLOW}Warning: Failed to backup WordPress paths file${NC}" >&2
                    }
                fi
                
                if [ -f "$DEFAULT_CONFIG_FILE" ]; then
                    cp "$DEFAULT_CONFIG_FILE" "$backup_dir/default_wp.ini.backup.$(date '+%Y%m%d%H%M%S')" || {
                        echo -e "${YELLOW}Warning: Failed to backup default WordPress config file${NC}" >&2
                    }
                fi
                
                # Reset files
                > "$WP_PATHS_FILE" || {
                    echo -e "${RED}Error: Failed to reset WordPress paths file${NC}" >&2
                    configure_plugin  # Recursive call
                    return 0
                }
                
                > "$DEFAULT_CONFIG_FILE" || {
                    echo -e "${RED}Error: Failed to reset default WordPress config file${NC}" >&2
                    configure_plugin  # Recursive call
                    return 0
                }
                
                echo -e "${GREEN}All saved WordPress paths have been reset.${NC}"
                echo -e "${GREEN}Backups saved to: $backup_dir${NC}"
            else
                echo -e "${YELLOW}Reset cancelled.${NC}"
            fi
            ;;
        6)
            echo -e "${BLUE}Returning to main menu.${NC}"
            return 0
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
    
    # Show the configuration menu again
    configure_plugin
    
    return 0
}

# Interactive mode - main loop
interactive_mode() {
    echo -e "${BLUE}WordPress Debug Plugin - Interactive Mode${NC}"
    
    while true; do
        # Select server
        local profile=$(select_server)
        
        if [ -z "$profile" ]; then
            # User chose to exit
            return 0
        fi
        
        # Server selected, enter server actions loop
        while true; do
            # Select action for the server
            if ! select_action "$profile"; then
                # User chose to go back
                break
            fi
        done
    done
}

# Main function
main() {
    # Check if running in interactive mode
    if [ $# -eq 0 ]; then
        # No arguments - full interactive mode
        interactive_mode
        return $?
    elif [ $# -eq 1 ]; then
        # One argument - server-specific interactive mode or help
        local profile="$1"
        
        # Check if the argument is a help flag
        if [ "$profile" = "help" ] || [ "$profile" = "--help" ] || [ "$profile" = "-h" ]; then
            show_usage
            return 0
        fi
        
        # Check if the profile exists
        if ! check_shellbe_profile "$profile"; then
            echo -e "${RED}Server profile '$profile' not found.${NC}"
            echo -e "${YELLOW}Available profiles:${NC}"
            get_shellbe_profiles | while read -r server; do
                if [ -n "$server" ]; then  # Skip empty lines
                    echo -e "${CYAN}- $server${NC}"
                fi
            done
            return 1
        fi
        
        # Enter server actions loop
        while true; do
            # Select action for the server
            if ! select_action "$profile"; then
                # User chose to go back
                return 0
            fi
        done
    else
        # Multiple arguments - direct command execution
        local profile="$1"
        local command="$2"
        shift 2
        
        # Check if the profile exists
        if ! check_shellbe_profile "$profile"; then
            echo -e "${RED}Server profile '$profile' not found.${NC}"
            echo -e "${YELLOW}Available profiles:${NC}"
get_shellbe_profiles | while read -r server; do
                if [ -n "$server" ]; then  # Skip empty lines
                    echo -e "${CYAN}- $server${NC}"
                fi
            done
            return 1
        fi
        
        # Execute the command
        case "$command" in
            "find")
                find_wp_config "$profile" "$@"
                ;;
            "list")
                list_wp_installations_interactive "$profile"
                ;;
            "status")
                check_debug_status "$profile" "$@"
                ;;
            "enable")
                enable_debugging "$profile" "$@"
                ;;
            "disable")
                disable_debugging "$profile" "$@"
                ;;
            "log")
                view_debug_log "$profile" "$@"
                ;;
            "configure")
                configure_debugging "$profile" "$@"
                ;;
            "default")
                select_wp_installation "$profile" "default"
                ;;
            "config")
                configure_plugin
                ;;
            "help"|"--help"|"-h")
                show_usage
                ;;
            *)
                echo -e "${RED}Unknown command: $command${NC}"
                show_usage
                return 1
                ;;
        esac
        
        return $?
    fi
}

# Run the plugin
main "$@"