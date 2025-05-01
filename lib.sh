#!/bin/bash
#
# WordPress Debug Plugin Library Functions
# Contains utility functions for the WP Debug plugin
#

# Plugin directory
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Path to saved WP config paths
WP_PATHS_FILE="$PLUGIN_DIR/wp_paths.ini"
DEFAULT_CONFIG_FILE="$PLUGIN_DIR/default_wp.ini"

# Create WP paths file if it doesn't exist
if [ ! -f "$WP_PATHS_FILE" ]; then
    touch "$WP_PATHS_FILE"
fi

# Create default WP config file if it doesn't exist
if [ ! -f "$DEFAULT_CONFIG_FILE" ]; then
    touch "$DEFAULT_CONFIG_FILE"
fi

# Execute SSH command on a remote server
shellbe_ssh_command() {
    local profile="$1"
    local command="$2"
    
    # Use shellbe to execute the command
    local output=$(shellbe connect "$profile" "$command" 2>/dev/null)
    
    # Return the output
    echo "$output"
}

# Get list of ShellBe profiles
get_shellbe_profiles() {
    local config_file="$HOME/.shellbe/config"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    cut -d: -f1 "$config_file"
}

# Check if a ShellBe profile exists
check_shellbe_profile() {
    local profile="$1"
    local config_file="$HOME/.shellbe/config"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    grep -q "^$profile:" "$config_file"
    return $?
}

# Save WordPress installation path for a profile
save_wp_installation() {
    local profile="$1"
    local path="$2"
    
    # Check if this path is already saved
    if grep -q "^$profile:" "$WP_PATHS_FILE" && grep -q "^$profile:.*:$path\$" "$WP_PATHS_FILE"; then
        return 0
    fi
    
    # Get existing paths for this profile
    local existing_paths=$(grep "^$profile:" "$WP_PATHS_FILE" | cut -d: -f2)
    
    if [ -n "$existing_paths" ]; then
        # Add to existing paths
        sed -i "/^$profile:/d" "$WP_PATHS_FILE"
        echo "$profile:$existing_paths:$path" >> "$WP_PATHS_FILE"
    else
        # First path for this profile
        echo "$profile:$path" >> "$WP_PATHS_FILE"
    fi
}

# Get saved WordPress installation paths for a profile
get_wp_installations() {
    local profile="$1"
    
    if [ ! -f "$WP_PATHS_FILE" ]; then
        return 1
    fi
    
    # Check if profile exists in the file
    if ! grep -q "^$profile:" "$WP_PATHS_FILE"; then
        return 1
    fi
    
    # Get the line for this profile
    local line=$(grep "^$profile:" "$WP_PATHS_FILE" | head -1)
    
    # Extract paths
    echo "$line" | cut -d: -f2- | tr ':' '\n'
}

# Clear saved WordPress installation paths for a profile
clear_wp_installations() {
    local profile="$1"
    
    if [ ! -f "$WP_PATHS_FILE" ]; then
        return 1
    fi
    
    # Remove profile line
    sed -i "/^$profile:/d" "$WP_PATHS_FILE"
    
    # Also remove from default config
    if [ -f "$DEFAULT_CONFIG_FILE" ]; then
        sed -i "/^$profile=/d" "$DEFAULT_CONFIG_FILE"
    fi
}

# Set default WordPress installation for a profile
save_default_wp_installation() {
    local profile="$1"
    local path="$2"
    
    # Remove any existing entry
    if [ -f "$DEFAULT_CONFIG_FILE" ]; then
        sed -i "/^$profile=/d" "$DEFAULT_CONFIG_FILE"
    fi
    
    # Add the new entry
    echo "$profile=$path" >> "$DEFAULT_CONFIG_FILE"
}

# Get default WordPress installation for a profile
get_default_wp_installation() {
    local profile="$1"
    
    if [ -f "$DEFAULT_CONFIG_FILE" ]; then
        grep "^$profile=" "$DEFAULT_CONFIG_FILE" | cut -d= -f2-
    fi
}

# Get a WordPress debug setting value
get_debug_setting() {
    local profile="$1"
    local wp_config_path="$2"
    local setting="$3"
    
    # Create a grep command to extract the setting
    local grep_cmd="grep -o \"define.*['\\\"]$setting['\\\"].*true\|define.*['\\\"]$setting['\\\"].*false\|define.*['\\\"]$setting['\\\"].*['\\\"].*['\\\"]\" \"$wp_config_path\""
    
    # Execute the command on the remote server
    local result=$(shellbe_ssh_command "$profile" "$grep_cmd")
    
    # Check if setting exists
    if [ -z "$result" ]; then
        echo "false"
        return 0
    fi
    
    # Extract the value
    if [[ "$result" =~ true ]]; then
        echo "true"
    elif [[ "$result" =~ false ]]; then
        echo "false"
    elif [[ "$result" =~ \"([^\"]+)\" ]]; then
        echo "\"${BASH_REMATCH[1]}\""
    elif [[ "$result" =~ \'([^\']+)\' ]]; then
        echo "'${BASH_REMATCH[1]}'"
    else
        echo "false"
    fi
}

# Set a WordPress debug setting
set_debug_setting() {
    local profile="$1"
    local wp_config_path="$2"
    local setting="$3"
    local value="$4"
    
    # Check if setting already exists
    local setting_exists=$(shellbe_ssh_command "$profile" "grep -c \"define.*['\\\"]$setting['\\\"]\" \"$wp_config_path\"")
    
    if [ "$setting_exists" -gt 0 ]; then
        # Setting exists, update it
        local sed_cmd="sed -i \"s/define(.*['\\\"]$setting['\\\"].*);/define( '$setting', $value );/\" \"$wp_config_path\""
        shellbe_ssh_command "$profile" "$sed_cmd"
    else
        # Setting doesn't exist, add it
        # First, try to find the section with other debug settings
        local debug_line=$(shellbe_ssh_command "$profile" "grep -n \"define.*['\\\"]WP_DEBUG['\\\"]\" \"$wp_config_path\" | cut -d: -f1")
        
        if [ -n "$debug_line" ]; then
            # Insert after WP_DEBUG line
            local line_number=$((debug_line + 1))
            local sed_cmd="sed -i \"${line_number}i define( '$setting', $value );\" \"$wp_config_path\""
            shellbe_ssh_command "$profile" "$sed_cmd"
        else
            # Try to find a reasonable place to insert
            local wp_config_end=$(shellbe_ssh_command "$profile" "grep -n \"/* That's all, stop editing\" \"$wp_config_path\" | cut -d: -f1")
            
            if [ -z "$wp_config_end" ]; then
                # Try another common pattern
                wp_config_end=$(shellbe_ssh_command "$profile" "grep -n \"require_once\" \"$wp_config_path\" | head -1 | cut -d: -f1")
            fi
            
            if [ -n "$wp_config_end" ]; then
                # Insert before this line
                local sed_cmd="sed -i \"${wp_config_end}i define( '$setting', $value );\" \"$wp_config_path\""
                shellbe_ssh_command "$profile" "$sed_cmd"
            else
                # Append to the end of the file
                local echo_cmd="echo \"define( '$setting', $value );\" >> \"$wp_config_path\""
                shellbe_ssh_command "$profile" "$echo_cmd"
            fi
        fi
    fi
}

# Create a backup of WordPress config file
create_config_backup() {
    local profile="$1"
    local wp_config_path="$2"
    
    # Get the directory and filename
    local dir_name=$(dirname "$wp_config_path")
    local file_name=$(basename "$wp_config_path")
    local timestamp=$(date +"%Y%m%d%H%M%S")
    local backup_path="$dir_name/${file_name}.backup.${timestamp}"
    
    # Create backup command
    local cp_cmd="cp \"$wp_config_path\" \"$backup_path\""
    
    # Execute the command
    shellbe_ssh_command "$profile" "$cp_cmd"
    
    echo "Backup created at $backup_path"
}

# List WordPress installations for a profile
list_wp_installations() {
    local profile="$1"
    local search_paths="${2:-/var/www/html,/home}"
    local search_depth="${3:-5}"
    
    # Build find command
    local find_cmd="find $search_paths -type f -name wp-config.php -maxdepth $search_depth 2>/dev/null"
    
    # Execute the command
    local results=$(shellbe_ssh_command "$profile" "$find_cmd")
    
    echo "$results"
}

# Check if debugging is enabled for a WordPress installation
is_debugging_enabled() {
    local profile="$1"
    local wp_config_path="$2"
    
    # Get WP_DEBUG setting
    local debug_status=$(get_debug_setting "$profile" "$wp_config_path" "WP_DEBUG")
    
    if [ "$debug_status" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# Get debug log path for a WordPress installation
get_debug_log_path() {
    local profile="$1"
    local wp_config_path="$2"
    
    # Get WP_DEBUG_LOG setting
    local debug_log=$(get_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG")
    
    if [[ "$debug_log" =~ ^[\"\']/.*[\"\']$ ]]; then
        # Custom log path
        echo "$debug_log" | sed 's/["\']//g'
    else
        # Default log path
        local wp_content_dir=$(dirname "$wp_config_path")/wp-content
        echo "$wp_content_dir/debug.log"
    fi
}

# Check if a WordPress site is in production mode
is_production_site() {
    local profile="$1"
    local wp_config_path="$2"
    
    # Check for production indicators in wp-config.php
    local grep_cmd="grep -E \"production|live|prod\" \"$wp_config_path\""
    local result=$(shellbe_ssh_command "$profile" "$grep_cmd")
    
    if [ -n "$result" ]; then
        return 0
    fi
    
    # Check for staging/development indicators
    local grep_cmd="grep -E \"staging|development|dev|test|local\" \"$wp_config_path\""
    local result=$(shellbe_ssh_command "$profile" "$grep_cmd")
    
    if [ -n "$result" ]; then
        return 1
    fi
    
    # Check domain in siteurl option
    local wp_dir=$(dirname "$wp_config_path")
    local table_prefix_cmd="grep \"table_prefix\" \"$wp_config_path\" | grep -o \"'[^']*'\\|\\\"[^\\\"]*\\\"\" | sed \"s/'//g\" | sed 's/\"//g'"
    local table_prefix=$(shellbe_ssh_command "$profile" "$table_prefix_cmd")
    
    # Default to wp_ if not found
    if [ -z "$table_prefix" ]; then
        table_prefix="wp_"
    fi
    
    # Try to get the site URL
    local site_url_cmd="cd $wp_dir && php -r 'include \"wp-config.php\"; \$conn = mysqli_connect(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME); if(\$conn) { \$result = mysqli_query(\$conn, \"SELECT option_value FROM ${table_prefix}options WHERE option_name = \\\"siteurl\\\" LIMIT 1\"); if(\$result && \$row = mysqli_fetch_assoc(\$result)) { echo \$row[\"option_value\"]; } mysqli_close(\$conn); }'"
    
    local site_url=$(shellbe_ssh_command "$profile" "$site_url_cmd")
    
    if [[ "$site_url" =~ \.(dev|test|stage|local|example)(\.|$) ]]; then
        return 1
    elif [[ "$site_url" =~ ^https?://localhost ]]; then
        return 1
    elif [[ "$site_url" =~ ^https?://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        # IP address - likely development
        return 1
    fi
    
    # Look for wp-admin logged in users
    local users_cmd="cd $wp_dir && find wp-content/uploads -name \"*.log\" -type f -mtime -7 | wc -l"
    local recent_logs=$(shellbe_ssh_command "$profile" "$users_cmd")
    
    if [ "$recent_logs" -gt 10 ]; then
        # Active site with many recent logs, likely production
        return 0
    fi
    
    # Default to assuming it's production
    return 0
}

# Get WordPress version
get_wp_version() {
    local profile="$1"
    local wp_dir=$(dirname "$2")
    
    local version_cmd="cd $wp_dir && grep \"wp_version =\" wp-includes/version.php | grep -o \"[0-9]\+\.[0-9]\+\.[0-9]\+\" || echo 'unknown'"
    local version=$(shellbe_ssh_command "$profile" "$version_cmd")
    
    echo "$version"
}

# Get PHP version
get_php_version() {
    local profile="$1"
    
    local version_cmd="php -v | grep -oE \"PHP [0-9]+\.[0-9]+\.[0-9]+\" | head -1 || echo 'unknown'"
    local version=$(shellbe_ssh_command "$profile" "$version_cmd")
    
    echo "$version"
}

# Parse WordPress error log
parse_error_log() {
    local profile="$1"
    local log_path="$2"
    local max_lines="${3:-100}"
    
    # Check if file exists
    local check_cmd="[ -f \"$log_path\" ] && echo 'exists' || echo 'not-exists'"
    local exists=$(shellbe_ssh_command "$profile" "$check_cmd")
    
    if [ "$exists" != "exists" ]; then
        echo "Log file does not exist"
        return 1
    fi
    
    # Get log file
    local log_content=$(shellbe_ssh_command "$profile" "tail -n $max_lines \"$log_path\"")
    
    # Parse errors and return structured output
    echo "$log_content" | grep -E "PHP (Fatal|Parse|Warning|Notice|Deprecated)" | sort | uniq -c | sort -nr
}

# Check WordPress file permissions
check_wp_permissions() {
    local profile="$1"
    local wp_dir=$(dirname "$2")
    
    # Check permissions of key directories
    local cmd="find $wp_dir -type d -name wp-content -o -name uploads -o -name plugins -o -name themes | xargs ls -ld"
    local dir_perms=$(shellbe_ssh_command "$profile" "$cmd")
    
    # Check if wp-config.php is readable by web server
    local config_perms=$(shellbe_ssh_command "$profile" "ls -l \"$2\"")
    
    echo -e "Directory permissions:\n$dir_perms\n\nConfig file:\n$config_perms"
}

# Get WordPress site name
get_wp_site_name() {
    local profile="$1"
    local wp_dir=$(dirname "$2")
    local table_prefix_cmd="grep \"table_prefix\" \"$2\" | grep -o \"'[^']*'\\|\\\"[^\\\"]*\\\"\" | sed \"s/'//g\" | sed 's/\"//g'"
    local table_prefix=$(shellbe_ssh_command "$profile" "$table_prefix_cmd")
    
    # Default to wp_ if not found
    if [ -z "$table_prefix" ]; then
        table_prefix="wp_"
    fi
    
    local site_name_cmd="cd $wp_dir && php -r 'include \"wp-config.php\"; \$conn = mysqli_connect(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME); if(\$conn) { \$result = mysqli_query(\$conn, \"SELECT option_value FROM ${table_prefix}options WHERE option_name = \\\"blogname\\\" LIMIT 1\"); if(\$result && \$row = mysqli_fetch_assoc(\$result)) { echo \$row[\"option_value\"]; } mysqli_close(\$conn); }'"
    
    local site_name=$(shellbe_ssh_command "$profile" "$site_name_cmd")
    
    echo "$site_name"
}

# Get WordPress active theme
get_wp_active_theme() {
    local profile="$1"
    local wp_dir=$(dirname "$2")
    local table_prefix_cmd="grep \"table_prefix\" \"$2\" | grep -o \"'[^']*'\\|\\\"[^\\\"]*\\\"\" | sed \"s/'//g\" | sed 's/\"//g'"
    local table_prefix=$(shellbe_ssh_command "$profile" "$table_prefix_cmd")
    
    # Default to wp_ if not found
    if [ -z "$table_prefix" ]; then
        table_prefix="wp_"
    fi
    
    local theme_cmd="cd $wp_dir && php -r 'include \"wp-config.php\"; \$conn = mysqli_connect(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME); if(\$conn) { \$result = mysqli_query(\$conn, \"SELECT option_value FROM ${table_prefix}options WHERE option_name = \\\"template\\\" LIMIT 1\"); if(\$result && \$row = mysqli_fetch_assoc(\$result)) { echo \$row[\"option_value\"]; } mysqli_close(\$conn); }'"
    
    local theme=$(shellbe_ssh_command "$profile" "$theme_cmd")
    
    echo "$theme"
}

# Get WordPress active plugins
get_wp_active_plugins() {
    local profile="$1"
    local wp_dir=$(dirname "$2")
    local table_prefix_cmd="grep \"table_prefix\" \"$2\" | grep -o \"'[^']*'\\|\\\"[^\\\"]*\\\"\" | sed \"s/'//g\" | sed 's/\"//g'"
    local table_prefix=$(shellbe_ssh_command "$profile" "$table_prefix_cmd")
    
    # Default to wp_ if not found
    if [ -z "$table_prefix" ]; then
        table_prefix="wp_"
    fi
    
    local plugins_cmd="cd $wp_dir && php -r 'include \"wp-config.php\"; \$conn = mysqli_connect(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME); if(\$conn) { \$result = mysqli_query(\$conn, \"SELECT option_value FROM ${table_prefix}options WHERE option_name = \\\"active_plugins\\\" LIMIT 1\"); if(\$result && \$row = mysqli_fetch_assoc(\$result)) { echo \$row[\"option_value\"]; } mysqli_close(\$conn); }'"
    
    local plugins=$(shellbe_ssh_command "$profile" "$plugins_cmd")
    
    # Parse PHP serialized array
    local plugin_count=$(echo "$plugins" | grep -o ":" | wc -l)
    
    echo "$plugin_count plugins active"
}

# Check if WordPress multisite is enabled
is_wp_multisite() {
    local profile="$1"
    local wp_config_path="$2"
    
    # Check for MULTISITE constant
    local multisite=$(get_debug_setting "$profile" "$wp_config_path" "MULTISITE")
    
    if [ "$multisite" = "true" ]; then
        return 0
    else
        return 1
    fi
}
