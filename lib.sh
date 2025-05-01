#!/bin/bash
#
# WordPress Debug Plugin Library Functions
# Contains utility functions for the WP Debug plugin
#

# Plugin directory
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$PLUGIN_DIR/templates"

# Path to saved WP config paths
WP_PATHS_FILE="$PLUGIN_DIR/wp_paths.ini"
DEFAULT_CONFIG_FILE="$PLUGIN_DIR/default_wp.ini"

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Create WP paths file if it doesn't exist
if [ ! -f "$WP_PATHS_FILE" ]; then
    touch "$WP_PATHS_FILE" || { echo -e "${RED}Error: Could not create WP paths file${NC}"; exit 1; }
fi

# Create default WP config file if it doesn't exist
if [ ! -f "$DEFAULT_CONFIG_FILE" ]; then
    touch "$DEFAULT_CONFIG_FILE" || { echo -e "${RED}Error: Could not create default WP config file${NC}"; exit 1; }
fi

# Load configuration from file
load_config() {
    local config_file="$PLUGIN_DIR/config.ini"
    local config_name="$1"
    local default_value="$2"

    if [ ! -f "$config_file" ]; then
        echo "$default_value"
        return
    fi

    local value=$(grep "^$config_name=" "$config_file" | cut -d= -f2-)
    if [ -z "$value" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# Safe path joining to avoid path traversal
safe_path_join() {
    local base_path="$1"
    local rel_path="$2"

    # Remove any leading slashes from rel_path to ensure it's relative
    rel_path="${rel_path#/}"

    # Remove any trailing slashes from base_path
    base_path="${base_path%/}"

    # Join paths with a slash
    echo "$base_path/$rel_path"
}

# Execute SSH command on a remote server with error handling
shellbe_ssh_command() {
    local profile="$1"
    local command="$2"
    local timeout="${3:-60}"  # Default timeout of 60 seconds

    # Validate inputs
    if [ -z "$profile" ]; then
        echo "Error: No profile specified for SSH command"
        return 1
    fi

    if [ -z "$command" ]; then
        echo "Error: No command specified for SSH execution"
        return 1
    fi

    # Use shellbe to execute the command with timeout
    local output
    output=$(timeout "$timeout" shellbe connect "$profile" "$command" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 124 ]; then
        echo "Error: Command timed out after $timeout seconds"
        return 124
    elif [ $exit_code -ne 0 ]; then
        # Only show error if specific error word is in the output
        if echo "$output" | grep -qi "error\|failed\|not found"; then
            echo "Error ($exit_code): $output"
        fi
        return $exit_code
    fi

    # Return the output
    echo "$output"
    return 0
}

# Get list of ShellBe profiles
get_shellbe_profiles() {
    local config_file="$HOME/.shellbe/config"

    if [ ! -f "$config_file" ]; then
        echo "Error: ShellBe config file not found at $config_file" >&2
        return 1
    fi

    cut -d: -f1 "$config_file"
    return $?
}

# Check if a ShellBe profile exists
check_shellbe_profile() {
    local profile="$1"
    local config_file="$HOME/.shellbe/config"

    if [ -z "$profile" ]; then
        echo "Error: No profile specified" >&2
        return 1
    fi

    if [ ! -f "$config_file" ]; then
        echo "Error: ShellBe config file not found at $config_file" >&2
        return 1
    fi

    grep -q "^$profile:" "$config_file"
    return $?
}

# Save WordPress installation path for a profile with path validation
save_wp_installation() {
    local profile="$1"
    local path="$2"

    # Input validation
    if [ -z "$profile" ]; then
        echo "Error: No profile specified" >&2
        return 1
    fi

    if [ -z "$path" ]; then
        echo "Error: No WordPress path specified" >&2
        return 1
    fi

    # Sanitize path (remove trailing slashes, etc.)
    path="${path%/}"

    # Check if this path is already saved
    if grep -q "^$profile:" "$WP_PATHS_FILE" && grep -q "^$profile:.*:$path\$" "$WP_PATHS_FILE"; then
        return 0
    fi

    # Get existing paths for this profile
    local existing_paths=$(grep "^$profile:" "$WP_PATHS_FILE" | cut -d: -f2-)

    if [ -n "$existing_paths" ]; then
        # Add to existing paths
        sed -i "/^$profile:/d" "$WP_PATHS_FILE"
        echo "$profile:$existing_paths:$path" >> "$WP_PATHS_FILE" || {
            echo "Error: Failed to update WP installations file" >&2
            return 1
        }
    else
        # First path for this profile
        echo "$profile:$path" >> "$WP_PATHS_FILE" || {
            echo "Error: Failed to update WP installations file" >&2
            return 1
        }
    fi

    return 0
}

# Get saved WordPress installation paths for a profile
get_wp_installations() {
    local profile="$1"

    if [ -z "$profile" ]; then
        echo "Error: No profile specified" >&2
        return 1
    fi

    if [ ! -f "$WP_PATHS_FILE" ]; then
        echo "Error: WordPress paths file not found at $WP_PATHS_FILE" >&2
        return 1
    fi

    # Check if profile exists in the file
    if ! grep -q "^$profile:" "$WP_PATHS_FILE"; then
        return 0  # Return empty, not an error
    fi

    # Get the line for this profile
    local line=$(grep "^$profile:" "$WP_PATHS_FILE" | head -1)

    # Extract paths
    echo "$line" | cut -d: -f2- | tr ':' '\n'
    return 0
}

# Clear saved WordPress installation paths for a profile
clear_wp_installations() {
    local profile="$1"

    if [ -z "$profile" ]; then
        echo "Error: No profile specified" >&2
        return 1
    fi

    if [ ! -f "$WP_PATHS_FILE" ]; then
        return 0  # File doesn't exist, nothing to clear
    fi

    # Remove profile line
    sed -i "/^$profile:/d" "$WP_PATHS_FILE" || {
        echo "Error: Failed to clear WordPress installations for $profile" >&2
        return 1
    }

    # Also remove from default config
    if [ -f "$DEFAULT_CONFIG_FILE" ]; then
        sed -i "/^$profile=/d" "$DEFAULT_CONFIG_FILE" || {
            echo "Error: Failed to clear default WordPress installation for $profile" >&2
            return 1
        }
    fi

    return 0
}

# Set default WordPress installation for a profile
save_default_wp_installation() {
    local profile="$1"
    local path="$2"

    # Input validation
    if [ -z "$profile" ]; then
        echo "Error: No profile specified" >&2
        return 1
    fi

    if [ -z "$path" ]; then
        echo "Error: No WordPress path specified" >&2
        return 1
    fi

    # Sanitize path (remove trailing slashes, etc.)
    path="${path%/}"

    # Remove any existing entry
    if [ -f "$DEFAULT_CONFIG_FILE" ]; then
        sed -i "/^$profile=/d" "$DEFAULT_CONFIG_FILE" || {
            echo "Error: Failed to update default WordPress installation for $profile" >&2
            return 1
        }
    fi

    # Add the new entry
    echo "$profile=$path" >> "$DEFAULT_CONFIG_FILE" || {
        echo "Error: Failed to save default WordPress installation for $profile" >&2
        return 1
    }

    return 0
}

# Get default WordPress installation for a profile
get_default_wp_installation() {
    local profile="$1"

    if [ -z "$profile" ]; then
        echo "Error: No profile specified" >&2
        return 1
    fi

    if [ ! -f "$DEFAULT_CONFIG_FILE" ]; then
        return 0  # File doesn't exist, return empty
    fi

    grep "^$profile=" "$DEFAULT_CONFIG_FILE" | cut -d= -f2-
    return 0
}

# Get a WordPress debug setting value
get_debug_setting() {
    local profile="$1"
    local wp_config_path="$2"
    local setting="$3"

    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_config_path" ] || [ -z "$setting" ]; then
        echo "Error: Missing required parameters for get_debug_setting" >&2
        return 1
    fi

    # Create a temporary grep script file
    local temp_script="/tmp/wpd_grep_${RANDOM}.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
grep -o "define.*['\\"]$setting['\\"].*true\\|define.*['\\"]$setting['\\"].*false\\|define.*['\\"]$setting['\\"].*['\\"].*['\\"]" "$wp_config_path"
EOF
    chmod +x "$temp_script"

    # Copy script to remote server
    local remote_script="/tmp/wpd_grep_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_script\"" < "$temp_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    local result=$(shellbe_ssh_command "$profile" "bash \"$remote_script\"")
    local exit_code=$?

    # Clean up temporary files
    rm -f "$temp_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_script\"" > /dev/null 2>&1

    if [ $exit_code -ne 0 ]; then
        echo "false"  # Default if command failed
        return 0
    fi

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

    return 0
}

# Set a WordPress debug setting with proper escaping
set_debug_setting() {
    local profile="$1"
    local wp_config_path="$2"
    local setting="$3"
    local value="$4"

    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_config_path" ] || [ -z "$setting" ]; then
        echo "Error: Missing required parameters for set_debug_setting" >&2
        return 1
    fi

    # Create a temporary script with the sed operations
    local temp_script="/tmp/wpd_set_debug_${RANDOM}.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
# Check if setting already exists
setting_exists=\$(grep -c "define.*['\\"]$setting['\\"]" "$wp_config_path")

if [ "\$setting_exists" -gt 0 ]; then
    # Setting exists, update it
    sed -i "s/define(.*['\\"]$setting['\\"].*);/define( '$setting', $value );/" "$wp_config_path"
    exit \$?
else
    # Setting doesn't exist, add it
    # First, try to find the section with other debug settings
    debug_line=\$(grep -n "define.*['\\"]WP_DEBUG['\\"]" "$wp_config_path" | cut -d: -f1)

    if [ -n "\$debug_line" ]; then
        # Insert after WP_DEBUG line
        line_number=\$((debug_line + 1))
        sed -i "\${line_number}i define( '$setting', $value );" "$wp_config_path"
        exit \$?
    else
        # Try to find a reasonable place to insert
        wp_config_end=\$(grep -n "/* That's all, stop editing" "$wp_config_path" | cut -d: -f1)

        if [ -z "\$wp_config_end" ]; then
            # Try another common pattern
            wp_config_end=\$(grep -n "require_once" "$wp_config_path" | head -1 | cut -d: -f1)
        fi

        if [ -n "\$wp_config_end" ]; then
            # Insert before this line
            sed -i "\${wp_config_end}i define( '$setting', $value );" "$wp_config_path"
            exit \$?
        else
            # Append to the end of the file
            echo "define( '$setting', $value );" >> "$wp_config_path"
            exit \$?
        fi
    fi
fi
EOF
    chmod +x "$temp_script"

    # Copy script to remote server
    local remote_script="/tmp/wpd_set_debug_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_script\"" < "$temp_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    shellbe_ssh_command "$profile" "bash \"$remote_script\""
    local exit_code=$?

    # Clean up temporary files
    rm -f "$temp_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_script\"" > /dev/null 2>&1

    return $exit_code
}

# Create a backup of WordPress config file
create_config_backup() {
    local profile="$1"
    local wp_config_path="$2"

    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_config_path" ]; then
        echo "Error: Missing required parameters for create_config_backup" >&2
        return 1
    fi

    # Get the directory and filename
    local dir_name=$(dirname "$wp_config_path")
    local file_name=$(basename "$wp_config_path")
    local timestamp=$(date +"%Y%m%d%H%M%S")
    local backup_path="$dir_name/${file_name}.backup.${timestamp}"

    # Create backup command
    local cp_cmd="cp \"$wp_config_path\" \"$backup_path\""

    # Execute the command
    shellbe_ssh_command "$profile" "$cp_cmd"
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "Error: Failed to create backup of wp-config.php" >&2
        return 1
    fi

    echo "Backup created at $backup_path"
    return 0
}

# List WordPress installations for a profile
list_wp_installations() {
    local profile="$1"
    local search_paths="${2:-/var/www/html,/home}"
    local search_depth="${3:-5}"

    # Input validation
    if [ -z "$profile" ]; then
        echo "Error: No profile specified" >&2
        return 1
    fi

    # Sanitize search paths to prevent command injection
    search_paths=$(echo "$search_paths" | tr -d ';&|$()')

    # Ensure search_depth is a number
    if ! [[ "$search_depth" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid search depth: $search_depth" >&2
        search_depth=5  # Default to safe value
    fi

    # Create a temporary script for the find operation
    local temp_script="/tmp/wpd_find_${RANDOM}.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
find $search_paths -type f -name wp-config.php -maxdepth $search_depth 2>/dev/null
EOF
    chmod +x "$temp_script"

    # Copy script to remote server
    local remote_script="/tmp/wpd_find_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_script\"" < "$temp_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    local results=$(shellbe_ssh_command "$profile" "bash \"$remote_script\"")
    local exit_code=$?

    # Clean up temporary files
    rm -f "$temp_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_script\"" > /dev/null 2>&1

    if [ $exit_code -ne 0 ]; then
        echo "Error: Failed to search for WordPress installations" >&2
        return 1
    fi

    echo "$results"
    return 0
}

# Check if debugging is enabled for a WordPress installation
is_debugging_enabled() {
    local profile="$1"
    local wp_config_path="$2"

    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_config_path" ]; then
        echo "Error: Missing required parameters for is_debugging_enabled" >&2
        return 1
    fi

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

    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_config_path" ]; then
        echo "Error: Missing required parameters for get_debug_log_path" >&2
        return 1
    fi

    # Get WP_DEBUG_LOG setting
    local debug_log=$(get_debug_setting "$profile" "$wp_config_path" "WP_DEBUG_LOG")

    if [[ "$debug_log" =~ ^[\"\']/.*[\"\']$ ]]; then
        # Custom log path - remove the quotes from the path
        echo "${debug_log:1:${#debug_log}-2}"
    else
        # Default log path
        local wp_content_dir=$(dirname "$wp_config_path")/wp-content
        echo "$wp_content_dir/debug.log"
    fi

    return 0
}

# Execute PHP code safely via SSH
execute_php_remote() {
    local profile="$1"
    local wp_dir="$2"
    local php_code="$3"

    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_dir" ] || [ -z "$php_code" ]; then
        echo "Error: Missing required parameters for execute_php_remote" >&2
        return 1
    fi

    # Create a temporary PHP file
    local temp_file="/tmp/wpd_temp_${RANDOM}.php"
    echo "<?php" > "$temp_file"
    echo "$php_code" >> "$temp_file"
    echo "?>" >> "$temp_file"

    # Copy script to remote server
    local remote_file="/tmp/wpd_temp_${RANDOM}.php"
    shellbe_ssh_command "$profile" "cat > \"$remote_file\"" < "$temp_file"

    # Execute the PHP file
    local result=$(shellbe_ssh_command "$profile" "cd $wp_dir && php $remote_file")
    local exit_code=$?

    # Clean up temporary files
    rm -f "$temp_file"
    shellbe_ssh_command "$profile" "rm -f \"$remote_file\"" > /dev/null 2>&1

    if [ $exit_code -ne 0 ]; then
        echo "Error: Failed to execute PHP code on remote server" >&2
        return 1
    fi

    echo "$result"
    return 0
}

# Get table prefix from wp-config.php safely
get_wp_table_prefix() {
    local profile="$1"
    local wp_config_path="$2"

    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_config_path" ]; then
        echo "Error: Missing required parameters for get_wp_table_prefix" >&2
        return 1
    fi

    # Create a temporary script to extract the table prefix
    local temp_script="/tmp/wpd_table_prefix_${RANDOM}.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
grep "table_prefix" "$wp_config_path" | grep -o "'[^']*'\\|\"[^\"]*\"" | sed "s/'//g" | sed 's/"//g'
EOF
    chmod +x "$temp_script"

    # Copy script to remote server
    local remote_script="/tmp/wpd_table_prefix_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_script\"" < "$temp_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    local table_prefix=$(shellbe_ssh_command "$profile" "bash \"$remote_script\"")
    local exit_code=$?

    # Clean up temporary files
    rm -f "$temp_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_script\"" > /dev/null 2>&1

    if [ $exit_code -ne 0 ] || [ -z "$table_prefix" ]; then
        # Default to wp_ if not found or error
        echo "wp_"
    else
        # Validate table prefix (only alphanumeric and underscore)
        if [[ "$table_prefix" =~ ^[a-zA-Z0-9_]+$ ]]; then
            echo "$table_prefix"
        else
            # Sanitize if it contains invalid characters
            echo "wp_"
        fi
    fi

    return 0
}

# Check if a WordPress site is in production mode
is_production_site() {
    local profile="$1"
    local wp_config_path="$2"

    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_config_path" ]; then
        echo "Error: Missing required parameters for is_production_site" >&2
        return 1
    fi

    # Create a temporary script to check for production indicators
    local temp_script="/tmp/wpd_check_prod_${RANDOM}.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
# Check for production indicators in wp-config.php
if grep -qE "production|live|prod" "$wp_config_path"; then
    echo "production"
    exit 0
fi

# Check for staging/development indicators
if grep -qE "staging|development|dev|test|local" "$wp_config_path"; then
    echo "development"
    exit 0
fi

# Default to unknown
echo "unknown"
EOF
    chmod +x "$temp_script"

    # Copy script to remote server
    local remote_script="/tmp/wpd_check_prod_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_script\"" < "$temp_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    local result=$(shellbe_ssh_command "$profile" "bash \"$remote_script\"")
    local exit_code=$?

    # Clean up temporary files
    rm -f "$temp_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_script\"" > /dev/null 2>&1

    if [ "$result" = "production" ]; then
        return 0
    elif [ "$result" = "development" ]; then
        return 1
    fi

    # Check domain in siteurl option
    local wp_dir=$(dirname "$wp_config_path")
    local table_prefix=$(get_wp_table_prefix "$profile" "$wp_config_path")

    # Create PHP code to check site URL
    local php_code="
    include \"wp-config.php\";
    try {
        \$conn = mysqli_connect(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME);
        if (!\$conn) {
            echo \"Database connection failed\";
            exit(1);
        }

        // Prepare query to prevent SQL injection
        \$stmt = mysqli_prepare(\$conn, \"SELECT option_value FROM ${table_prefix}options WHERE option_name = ? LIMIT 1\");
        mysqli_stmt_bind_param(\$stmt, 's', \$option_name);
        \$option_name = 'siteurl';

        if (mysqli_stmt_execute(\$stmt)) {
            mysqli_stmt_bind_result(\$stmt, \$option_value);
            if (mysqli_stmt_fetch(\$stmt)) {
                echo \$option_value;
            }
        }

        mysqli_stmt_close(\$stmt);
        mysqli_close(\$conn);
    } catch (Exception \$e) {
        echo \"Error: \" . \$e->getMessage();
        exit(1);
    }
    "

    local site_url=$(execute_php_remote "$profile" "$wp_dir" "$php_code")

    if [[ "$site_url" =~ \.(dev|test|stage|local|example)(\.|$) ]]; then
        return 1
    elif [[ "$site_url" =~ ^https?://localhost ]]; then
        return 1
    elif [[ "$site_url" =~ ^https?://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        # IP address - likely development
        return 1
    fi

    # Look for wp-admin logged in users
    local logs_script="/tmp/wpd_check_logs_${RANDOM}.sh"
    cat > "$logs_script" << EOF
#!/bin/bash
cd $wp_dir && find wp-content/uploads -name "*.log" -type f -mtime -7 | wc -l
EOF
    chmod +x "$logs_script"

    # Copy script to remote server
    local remote_logs_script="/tmp/wpd_check_logs_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_logs_script\"" < "$logs_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_logs_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    local recent_logs=$(shellbe_ssh_command "$profile" "bash \"$remote_logs_script\"")

    # Clean up temporary files
    rm -f "$logs_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_logs_script\"" > /dev/null 2>&1

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

    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_dir" ]; then
        echo "Error: Missing required parameters for get_wp_version" >&2
        return 1
    fi

    # Create a temporary script to extract the WordPress version
    local temp_script="/tmp/wpd_wp_version_${RANDOM}.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
cd $wp_dir && grep "wp_version =" wp-includes/version.php | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" || echo 'unknown'
EOF
    chmod +x "$temp_script"

    # Copy script to remote server
    local remote_script="/tmp/wpd_wp_version_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_script\"" < "$temp_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    local version=$(shellbe_ssh_command "$profile" "bash \"$remote_script\"")
    local exit_code=$?

    # Clean up temporary files
    rm -f "$temp_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_script\"" > /dev/null 2>&1

    if [ $exit_code -ne 0 ]; then
        echo "unknown"
    else
        echo "$version"
    fi

    return 0
}

# Get PHP version
get_php_version() {
    local profile="$1"

    # Input validation
    if [ -z "$profile" ]; then
        echo "Error: No profile specified" >&2
        return 1
    fi

    # Create a temporary script to get the PHP version
    local temp_script="/tmp/wpd_php_version_${RANDOM}.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
php -v | grep -oE "PHP [0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo 'unknown'
EOF
    chmod +x "$temp_script"

    # Copy script to remote server
    local remote_script="/tmp/wpd_php_version_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_script\"" < "$temp_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    local version=$(shellbe_ssh_command "$profile" "bash \"$remote_script\"")
    local exit_code=$?

    # Clean up temporary files
    rm -f "$temp_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_script\"" > /dev/null 2>&1

    if [ $exit_code -ne 0 ]; then
        echo "unknown"
    else
        echo "$version"
    fi

    return 0
}

# Parse WordPress error log
parse_error_log() {
    local profile="$1"
    local log_path="$2"
    local max_lines="${3:-100}"

    # Input validation
    if [ -z "$profile" ] || [ -z "$log_path" ]; then
        echo "Error: Missing required parameters for parse_error_log" >&2
        return 1
    fi

    # Ensure max_lines is a number
    if ! [[ "$max_lines" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid max lines: $max_lines" >&2
        max_lines=100  # Default to safe value
    fi

    # Create a temporary script to check if the log file exists
    local check_script="/tmp/wpd_check_log_${RANDOM}.sh"
    cat > "$check_script" << EOF
#!/bin/bash
if [ -f "$log_path" ]; then
    echo "exists"
else
    echo "not-exists"
fi
EOF
    chmod +x "$check_script"

    # Copy script to remote server
    local remote_check_script="/tmp/wpd_check_log_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_check_script\"" < "$check_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_check_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    local exists=$(shellbe_ssh_command "$profile" "bash \"$remote_check_script\"")

    # Clean up temporary files
    rm -f "$check_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_check_script\"" > /dev/null 2>&1

    if [ "$exists" != "exists" ]; then
        echo "Log file does not exist"
        return 1
    fi

    # Create a temporary script to parse the error log
    local parse_script="/tmp/wpd_parse_log_${RANDOM}.sh"
    cat > "$parse_script" << EOF
#!/bin/bash
tail -n $max_lines "$log_path" | grep -E "PHP (Fatal|Parse|Warning|Notice|Deprecated)" | sort | uniq -c | sort -nr
EOF
    chmod +x "$parse_script"

    # Copy script to remote server
    local remote_parse_script="/tmp/wpd_parse_log_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_parse_script\"" < "$parse_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_parse_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    local result=$(shellbe_ssh_command "$profile" "bash \"$remote_parse_script\"")
    local exit_code=$?

    # Clean up temporary files
    rm -f "$parse_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_parse_script\"" > /dev/null 2>&1

    if [ $exit_code -ne 0 ]; then
        echo "Error: Failed to parse log file"
        return 1
    fi

    echo "$result"
    return 0
}

# Check WordPress file permissions
check_wp_permissions() {
    local profile="$1"
    local wp_dir=$(dirname "$2")

    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_dir" ]; then
        echo "Error: Missing required parameters for check_wp_permissions" >&2
        return 1
    fi

    # Create a temporary script to check permissions
    local temp_script="/tmp/wpd_check_perms_${RANDOM}.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
echo "Directory permissions:"
find $wp_dir -type d -name wp-content -o -name uploads -o -name plugins -o -name themes | xargs ls -ld
echo ""
echo "Config file:"
ls -l "$2"
EOF
    chmod +x "$temp_script"

    # Copy script to remote server
    local remote_script="/tmp/wpd_check_perms_${RANDOM}.sh"
    shellbe_ssh_command "$profile" "cat > \"$remote_script\"" < "$temp_script"
    shellbe_ssh_command "$profile" "chmod +x \"$remote_script\"" > /dev/null 2>&1

    # Execute the script on the remote server
    local result=$(shellbe_ssh_command "$profile" "bash \"$remote_script\"")
    local exit_code=$?

    # Clean up temporary files
    rm -f "$temp_script"
    shellbe_ssh_command "$profile" "rm -f \"$remote_script\"" > /dev/null 2>&1

    if [ $exit_code -ne 0 ]; then
        echo "Error: Failed to check permissions"
        return 1
    fi

    echo "$result"
    return 0
}

# Get WordPress site name
get_wp_site_name() {
    local profile="$1"
    local wp_dir=$(dirname "$2")
    local table_prefix=$(get_wp_table_prefix "$profile" "$2")

    # Create PHP code to get site name
    local php_code="
    include \"wp-config.php\";
    try {
        \$conn = mysqli_connect(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME);
        if (!\$conn) {
            echo \"Database connection failed\";
            exit(1);
        }

        // Prepare query to prevent SQL injection
        \$stmt = mysqli_prepare(\$conn, \"SELECT option_value FROM ${table_prefix}options WHERE option_name = ? LIMIT 1\");
        mysqli_stmt_bind_param(\$stmt, 's', \$option_name);
        \$option_name = 'blogname';

        if (mysqli_stmt_execute(\$stmt)) {
            mysqli_stmt_bind_result(\$stmt, \$option_value);
            if (mysqli_stmt_fetch(\$stmt)) {
                echo \$option_value;
            }
        }

        mysqli_stmt_close(\$stmt);
        mysqli_close(\$conn);
    } catch (Exception \$e) {
        echo \"Error: \" . \$e->getMessage();
        exit(1);
    }
    "

    # Execute the PHP code
    local site_name=$(execute_php_remote "$profile" "$wp_dir" "$php_code")

    echo "$site_name"
    return 0
}

# Get WordPress active theme
get_wp_active_theme() {
    local profile="$1"
    local wp_dir=$(dirname "$2")
    local table_prefix=$(get_wp_table_prefix "$profile" "$2")

    # Create PHP code to get active theme
    local php_code="
    include \"wp-config.php\";
    try {
        \$conn = mysqli_connect(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME);
        if (!\$conn) {
            echo \"Database connection failed\";
            exit(1);
        }

        // Prepare query to prevent SQL injection
        \$stmt = mysqli_prepare(\$conn, \"SELECT option_value FROM ${table_prefix}options WHERE option_name = ? LIMIT 1\");
        mysqli_stmt_bind_param(\$stmt, 's', \$option_name);
        \$option_name = 'template';

        if (mysqli_stmt_execute(\$stmt)) {
            mysqli_stmt_bind_result(\$stmt, \$option_value);
            if (mysqli_stmt_fetch(\$stmt)) {
                echo \$option_value;
            }
        }

        mysqli_stmt_close(\$stmt);
        mysqli_close(\$conn);
    } catch (Exception \$e) {
        echo \"Error: \" . \$e->getMessage();
        exit(1);
    }
    "

    # Execute the PHP code
    local theme=$(execute_php_remote "$profile" "$wp_dir" "$php_code")

    echo "$theme"
    return 0
}

# Get WordPress active plugins
get_wp_active_plugins() {
    local profile="$1"
    local wp_dir=$(dirname "$2")
    local table_prefix=$(get_wp_table_prefix "$profile" "$2")

    # Create PHP code to get active plugins
    local php_code="
    include \"wp-config.php\";
    try {
        \$conn = mysqli_connect(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME);
        if (!\$conn) {
            echo \"Database connection failed\";
            exit(1);
        }

        // Prepare query to prevent SQL injection
        \$stmt = mysqli_prepare(\$conn, \"SELECT option_value FROM ${table_prefix}options WHERE option_name = ? LIMIT 1\");
        mysqli_stmt_bind_param(\$stmt, 's', \$option_name);
        \$option_name = 'active_plugins';

        if (mysqli_stmt_execute(\$stmt)) {
            mysqli_stmt_bind_result(\$stmt, \$option_value);
            if (mysqli_stmt_fetch(\$stmt)) {
                // Just count the serialized values
                \$plugin_count = substr_count(\$option_value, 's:');
                echo \$plugin_count . \" plugins active\";
            } else {
                echo \"0 plugins active\";
            }
        }

        mysqli_stmt_close(\$stmt);
        mysqli_close(\$conn);
    } catch (Exception \$e) {
        echo \"Error: \" . \$e->getMessage();
        exit(1);
    }
    "

    # Execute the PHP code
    local plugins=$(execute_php_remote "$profile" "$wp_dir" "$php_code")
    
    echo "$plugins"
    return 0
}

# Check if WordPress multisite is enabled
is_wp_multisite() {
    local profile="$1"
    local wp_config_path="$2"
    
    # Input validation
    if [ -z "$profile" ] || [ -z "$wp_config_path" ]; then
        echo "Error: Missing required parameters for is_wp_multisite" >&2
        return 1
    fi
    
    # Check for MULTISITE constant
    local multisite=$(get_debug_setting "$profile" "$wp_config_path" "MULTISITE")
    
    if [ "$multisite" = "true" ]; then
        return 0
    else
        return 1
    fi
}