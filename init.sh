#!/bin/bash
#
# WordPress Debug Plugin - Initialization Script
# Run when the plugin is first enabled
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

echo -e "${BLUE}Initializing WordPress Debug Plugin (WPD)...${NC}"

# Create necessary directories
mkdir -p "$PLUGIN_DIR/hooks" || {
    echo -e "${RED}Error: Failed to create hooks directory${NC}" >&2
    exit 1
}

# Ensure all scripts are executable
for script in "$PLUGIN_DIR"/plugin.sh "$PLUGIN_DIR"/lib.sh "$PLUGIN_DIR"/init.sh; do
    if [ -f "$script" ]; then
        chmod +x "$script" || {
            echo -e "${RED}Error: Failed to make $script executable${NC}" >&2
            exit 1
        }
    else
        echo -e "${RED}Error: Required script $script not found${NC}" >&2
        exit 1
    fi
done

if [ -f "$PLUGIN_DIR/cleanup.sh" ]; then
    chmod +x "$PLUGIN_DIR/cleanup.sh" || {
        echo -e "${RED}Warning: Failed to make cleanup.sh executable${NC}" >&2
    }
fi

# Make hook scripts executable
for hook_script in "$PLUGIN_DIR/hooks"/*.sh; do
    if [ -f "$hook_script" ]; then
        chmod +x "$hook_script" || {
            echo -e "${RED}Warning: Failed to make hook script $hook_script executable${NC}" >&2
        }
    fi
done

# Create config file if it doesn't exist
if [ ! -f "$PLUGIN_DIR/config.ini" ]; then
    cat > "$PLUGIN_DIR/config.ini" << EOF
# WordPress Debug Plugin Configuration
# Generated: $(date +"%Y-%m-%d %H:%M:%S")

# Comma-separated list of paths to search for WordPress installations
default_search_paths=/var/www/html,/srv/www,/home

# Maximum depth to search for WordPress installations
max_search_depth=5

# Whether to create a backup of wp-config.php before making changes
backup_before_changes=true

# Maximum number of log lines to display
debug_log_limit=1000
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Created default configuration.${NC}"
    else
        echo -e "${RED}Error: Failed to create configuration file${NC}" >&2
        exit 1
    fi
fi

# Create WordPress paths file if it doesn't exist
if [ ! -f "$PLUGIN_DIR/wp_paths.ini" ]; then
    touch "$PLUGIN_DIR/wp_paths.ini" || {
        echo -e "${RED}Error: Failed to create WordPress paths file${NC}" >&2
        exit 1
    }
    echo -e "${GREEN}Created WordPress paths file.${NC}"
fi

# Create default WordPress selection file if it doesn't exist
if [ ! -f "$PLUGIN_DIR/default_wp.ini" ]; then
    touch "$PLUGIN_DIR/default_wp.ini" || {
        echo -e "${RED}Error: Failed to create default WordPress selection file${NC}" >&2
        exit 1
    }
    echo -e "${GREEN}Created default WordPress selection file.${NC}"
fi

# Check for existing ShellBe profiles
CONFIG_DIR="$HOME/.shellbe"
if [ -f "$CONFIG_DIR/config" ]; then
    echo -e "${BLUE}Checking for existing WordPress installations on saved profiles...${NC}"
    
    # Count of profiles with WordPress
    found_wp=0
    
    # Read profiles from config
    while IFS=: read -r name host user port identity options; do
        if [ -z "$name" ]; then
            continue  # Skip empty lines
        }
        
        echo -e "${YELLOW}Checking profile '$name'... ${NC}"
        
        # Check if we can connect to the server
        if shellbe_ssh_command "$name" "echo 'Connected'" | grep -q "Connected"; then
            echo -e "  ${GREEN}Connection successful${NC}"
            
            # Look for WordPress installations
            echo -e "  ${YELLOW}Searching for WordPress installations (this may take a moment)...${NC}"
            
            # Get default search paths from config
            DEFAULT_SEARCH_PATHS=$(grep "^default_search_paths=" "$PLUGIN_DIR/config.ini" | cut -d= -f2)
            MAX_SEARCH_DEPTH=$(grep "^max_search_depth=" "$PLUGIN_DIR/config.ini" | cut -d= -f2)
            
            if [ -z "$DEFAULT_SEARCH_PATHS" ]; then
                DEFAULT_SEARCH_PATHS="/var/www/html,/srv/www,/home"
            fi
            
            if [ -z "$MAX_SEARCH_DEPTH" ] || ! [[ "$MAX_SEARCH_DEPTH" =~ ^[0-9]+$ ]]; then
                MAX_SEARCH_DEPTH=5
            fi
            
            # Sanitize paths for security
            DEFAULT_SEARCH_PATHS=$(echo "$DEFAULT_SEARCH_PATHS" | tr -d ';&|$()')
            
            wp_installations=$(list_wp_installations "$name" "$DEFAULT_SEARCH_PATHS" "$MAX_SEARCH_DEPTH")
            
            if [ -n "$wp_installations" ]; then
                installation_count=$(echo "$wp_installations" | wc -l)
                echo -e "  ${GREEN}Found $installation_count WordPress installation(s)${NC}"
                
                # Save all found installations
                clear_wp_installations "$name"
                
                # Process each installation
                while IFS= read -r wp_path; do
                    if [ -n "$wp_path" ]; then  # Skip empty lines
                        if save_wp_installation "$name" "$wp_path"; then
                            echo -e "  ${GREEN}Saved:${NC} $wp_path"
                        else
                            echo -e "  ${RED}Failed to save:${NC} $wp_path"
                        fi
                    fi
                done <<< "$wp_installations"
                
                # If only one installation found, set it as default
                if [ "$installation_count" -eq 1 ]; then
                    if save_default_wp_installation "$name" "$wp_installations"; then
                        echo -e "  ${GREEN}Set as default WordPress installation${NC}"
                    else
                        echo -e "  ${RED}Failed to set default WordPress installation${NC}"
                    fi
                else
                    # Ask if user wants to set a default
                    read -p "  Do you want to set a default WordPress installation for '$name'? (y/n): " set_default
                    if [[ "$set_default" == "y" || "$set_default" == "Y" ]]; then
                        # Display numbered list of installations
                        echo -e "  ${YELLOW}Select default WordPress installation:${NC}"
                        
                        i=1
                        wp_paths=()
                        
                        while IFS= read -r path; do
                            if [ -n "$path" ]; then  # Skip empty lines
                                wp_paths+=("$path")
                                echo -e "  ${CYAN}$i)${NC} $path"
                                i=$((i + 1))
                            fi
                        done <<< "$wp_installations"
                        
                        # Get user selection
                        read -p "  Enter selection number: " selection
                        
                        # Validate selection
                        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ] && [ "$selection" -le "${#wp_paths[@]}" ]; then
                            selected_path="${wp_paths[$((selection - 1))]}"
                            if save_default_wp_installation "$name" "$selected_path"; then
                                echo -e "  ${GREEN}Set default WordPress installation to:${NC} $selected_path"
                            else
                                echo -e "  ${RED}Failed to set default WordPress installation${NC}"
                            fi
                        else
                            echo -e "  ${RED}Invalid selection. No default set.${NC}"
                        fi
                    fi
                fi
                
                found_wp=$((found_wp + 1))
            else
                echo -e "  ${YELLOW}No WordPress installations found${NC}"
            fi
        else
            echo -e "  ${RED}Connection failed${NC}"
        fi
        
        echo ""
    done < "$CONFIG_DIR/config"
    
    if [ "$found_wp" -gt 0 ]; then
        echo -e "${GREEN}Saved WordPress paths for $found_wp profile(s)${NC}"
    else
        echo -e "${YELLOW}No WordPress installations found on any profile${NC}"
    fi
fi

# Create symbolic link for easier command access
SHELLBE_PLUGINS_DIR="$HOME/.shellbe/plugins"
if [ -d "$SHELLBE_PLUGINS_DIR" ]; then
    if [ ! -L "$SHELLBE_PLUGINS_DIR/wpd" ] && [ "$PLUGIN_DIR" != "$SHELLBE_PLUGINS_DIR/wpd" ]; then
        ln -sf "$PLUGIN_DIR" "$SHELLBE_PLUGINS_DIR/wpd" || {
            echo -e "${YELLOW}Warning: Failed to create symbolic link. Plugin will still work.${NC}"
        }
        if [ -L "$SHELLBE_PLUGINS_DIR/wpd" ]; then
            echo -e "${GREEN}Created symbolic link for easy access${NC}"
        fi
    fi
fi

echo -e "${GREEN}WordPress Debug Plugin (WPD) initialized successfully!${NC}"
echo -e "${BLUE}Use '${CYAN}shellbe wpd${BLUE}' to manage WordPress debugging${NC}"