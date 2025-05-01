#!/bin/bash
#
# WordPress Debug Plugin - Initialization Script
# Run when the plugin is first enabled
#

# Get plugin directory
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}Initializing WordPress Debug Plugin (WPD)...${NC}"

# Create necessary directories
mkdir -p "$PLUGIN_DIR/hooks"

# Ensure all scripts are executable
chmod +x "$PLUGIN_DIR/plugin.sh"
chmod +x "$PLUGIN_DIR/lib.sh"
chmod +x "$PLUGIN_DIR/init.sh"

if [ -f "$PLUGIN_DIR/cleanup.sh" ]; then
    chmod +x "$PLUGIN_DIR/cleanup.sh"
fi

# Make hook scripts executable
for hook_script in "$PLUGIN_DIR/hooks"/*.sh; do
    if [ -f "$hook_script" ]; then
        chmod +x "$hook_script"
    fi
done

# Create config file if it doesn't exist
if [ ! -f "$PLUGIN_DIR/config.ini" ]; then
    echo "# WordPress Debug Plugin Configuration" > "$PLUGIN_DIR/config.ini"
    echo "default_search_paths=/var/www/html,/srv/www,/home" >> "$PLUGIN_DIR/config.ini"
    echo "max_search_depth=5" >> "$PLUGIN_DIR/config.ini"
    echo "backup_before_changes=true" >> "$PLUGIN_DIR/config.ini"
    echo "debug_log_limit=1000" >> "$PLUGIN_DIR/config.ini"
    
    echo -e "${GREEN}Created default configuration.${NC}"
fi

# Create WordPress paths file if it doesn't exist
if [ ! -f "$PLUGIN_DIR/wp_paths.ini" ]; then
    touch "$PLUGIN_DIR/wp_paths.ini"
    echo -e "${GREEN}Created WordPress paths file.${NC}"
fi

# Create default WordPress selection file if it doesn't exist
if [ ! -f "$PLUGIN_DIR/default_wp.ini" ]; then
    touch "$PLUGIN_DIR/default_wp.ini"
    echo -e "${GREEN}Created default WordPress selection file.${NC}"
fi

# Check for existing ShellBe profiles
CONFIG_DIR="$HOME/.shellbe"
if [ -f "$CONFIG_DIR/config" ]; then
    echo -e "${BLUE}Checking for existing WordPress installations on saved profiles...${NC}"
    
    # Source library functions
    source "$PLUGIN_DIR/lib.sh"
    
    # Count of profiles with WordPress
    found_wp=0
    
    # Read profiles from config
    while IFS=: read -r name host user port identity options; do
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
            
            if [ -z "$MAX_SEARCH_DEPTH" ]; then
                MAX_SEARCH_DEPTH=5
            fi
            
            wp_installations=$(list_wp_installations "$name" "$DEFAULT_SEARCH_PATHS" "$MAX_SEARCH_DEPTH")
            
            if [ -n "$wp_installations" ]; then
                installation_count=$(echo "$wp_installations" | wc -l)
                echo -e "  ${GREEN}Found $installation_count WordPress installation(s)${NC}"
                
                # Save all found installations
                clear_wp_installations "$name"
                
                # Process each installation
                while IFS= read -r wp_path; do
                    save_wp_installation "$name" "$wp_path"
                    echo -e "  ${GREEN}Saved:${NC} $wp_path"
                done <<< "$wp_installations"
                
                # If only one installation found, set it as default
                if [ "$installation_count" -eq 1 ]; then
                    save_default_wp_installation "$name" "$wp_installations"
                    echo -e "  ${GREEN}Set as default WordPress installation${NC}"
                else
                    # Ask if user wants to set a default
                    read -p "  Do you want to set a default WordPress installation for '$name'? (y/n): " set_default
                    if [[ "$set_default" == "y" || "$set_default" == "Y" ]]; then
                        # Display numbered list of installations
                        echo -e "  ${YELLOW}Select default WordPress installation:${NC}"
                        
                        local i=1
                        local wp_paths=()
                        
                        while IFS= read -r path; do
                            wp_paths+=("$path")
                            echo -e "  ${CYAN}$i)${NC} $path"
                            i=$((i + 1))
                        done <<< "$wp_installations"
                        
                        # Get user selection
                        local selection
                        read -p "  Enter selection number: " selection
                        
                        # Validate selection
                        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ] && [ "$selection" -le "${#wp_paths[@]}" ]; then
                            local selected_path="${wp_paths[$((selection - 1))]}"
                            save_default_wp_installation "$name" "$selected_path"
                            echo -e "  ${GREEN}Set default WordPress installation to:${NC} $selected_path"
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
    fi
fi

# Create symbolic link for easier command access
SHELLBE_PLUGINS_DIR="$HOME/.shellbe/plugins"
if [ -d "$SHELLBE_PLUGINS_DIR" ]; then
    if [ ! -L "$SHELLBE_PLUGINS_DIR/wpd" ] && [ "$PLUGIN_DIR" != "$SHELLBE_PLUGINS_DIR/wpd" ]; then
        ln -sf "$PLUGIN_DIR" "$SHELLBE_PLUGINS_DIR/wpd"
        echo -e "${GREEN}Created symbolic link for easy access${NC}"
    fi
fi

echo -e "${GREEN}WordPress Debug Plugin (WPD) initialized successfully!${NC}"
echo -e "${BLUE}Use '${CYAN}shellbe wpd${BLUE}' to manage WordPress debugging${NC}"
