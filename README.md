# WordPress Debug Plugin for ShellBe

A robust plugin for managing WordPress debugging settings across multiple remote servers. Securely enable, disable, and monitor WordPress debugging through a simple CLI interface.

## Features

- Find WordPress installations on remote servers
- Enable/disable debugging with a single command
- Configure multiple debugging options (WP_DEBUG, WP_DEBUG_LOG, WP_DEBUG_DISPLAY, etc.)
- Safe production environment detection to prevent accidental debugging in production
- View and analyze WordPress debug logs
- Set default WordPress installations for quicker access
- Automatic configuration backup before making changes
- Secure database operations with proper SQL injection protection
- Enhanced error handling and path safety

## Installation

1. Clone this repository to your local machine:
   ```
   git clone https://github.com/eraxe/shellbe-wpd.git ~/.shellbe/plugins/wpd
   ```

2. Alternatively, you can install the plugin through ShellBe's plugin manager:
   ```
   shellbe plugin install wpd
   ```

3. Enable the plugin:
   ```
   shellbe plugin enable wpd
   ```

## Usage

### Interactive Mode

Simply run:
```
shellbe wpd
```

This will guide you through selecting a server and WordPress installation to manage.

### Server-Specific Interactive Mode

```
shellbe wpd <server-profile>
```

This launches interactive mode for a specific server.

### Direct Commands

```
shellbe wpd <server-profile> <command> [options]
```

Available commands:

- `find`: Find WordPress installations on a server
- `list`: List existing WordPress installations
- `status`: Check WordPress debugging status
- `enable`: Enable WordPress debugging
- `disable`: Disable WordPress debugging
- `log`: View WordPress debug logs
- `configure`: Configure debugging settings
- `default`: Set default WordPress installation
- `config`: Configure plugin settings
- `help`: Show usage information

### Examples

Find WordPress installations:
```
shellbe wpd myserver find
```

Check debugging status:
```
shellbe wpd myserver status
```

Enable debugging with custom settings:
```
shellbe wpd myserver enable --display=false --script-debug=true
```

View debug log:
```
shellbe wpd myserver log --limit=50
```

## Security Enhancements

Version 1.1.0 includes several security and stability improvements:

- SQL Injection Protection: All database operations now use prepared statements
- Input Validation: Proper validation and sanitization for all user and remote inputs
- Path Traversal Prevention: Safe path handling to prevent directory traversal attacks
- Enhanced Error Handling: Robust error checking with meaningful error messages
- Safer Configuration Management: Improved handling of configuration files
- Command Execution Safety: Protection against command injection in shell commands

## Configuration

Configuration is stored in `~/.shellbe/plugins/wpd/config.ini` and can be modified through the `config` command:

```
shellbe wpd config
```

## Hooks

The plugin integrates with ShellBe through hooks:

- `pre_connect.sh`: Shows debugging status before connecting
- `post_connect.sh`: Notifies about debug logs and new WordPress installations
- `profile_info.sh`: Displays WordPress information when viewing server profiles

## Automatic Backup

The plugin automatically creates backups of your wp-config.php files before making changes. This behavior can be configured with the `backup_before_changes` setting.

## License

MIT License - See LICENSE file for details