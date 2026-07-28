#!/usr/bin/env fish
# fpm.fish - Fish Plugin Manager (Enhanced)
# A lightweight but powerful plugin manager for fish shell

# ============================================
# Core Configuration
# ============================================
set -gx FPM_HOME $HOME/.config/fish/fpm
set -gx FPM_PLUGINS $FPM_HOME/plugins
set -gx FPM_THEMES $FPM_HOME/themes
set -gx FPM_PLUGIN_FILE $FPM_HOME/plugins.txt
set -gx FPM_CONFIG $FPM_HOME/config.fish
set -gx FPM_CACHE $FPM_HOME/cache
set -gx FPM_REGISTRY $FPM_HOME/registry.json
set -gx FPM_VERSION "1.0.0"

# Initialize directories
for dir in $FPM_HOME $FPM_PLUGINS $FPM_THEMES $FPM_CACHE
    if not test -d $dir
        mkdir -p $dir
    end
end

if not test -f $FPM_PLUGIN_FILE
    touch $FPM_PLUGIN_FILE
end

if not test -f $FPM_CONFIG
    echo "# fpm configuration" > $FPM_CONFIG
    echo "set -g fpm_auto_update false" >> $FPM_CONFIG
    echo "set -g fpm_verbose true" >> $FPM_CONFIG
    echo "set -g fpm_theme default" >> $FPM_CONFIG
end

# Load config
source $FPM_CONFIG 2>/dev/null

# ============================================
# Main Command
# ============================================
function fpm -d "Fish Plugin Manager"
    set -l subcommand $argv[1]

    switch $subcommand
        case help --help -h
            __fpm_help
        case install i
            __fpm_install $argv[2..-1]
        case uninstall remove rm
            __fpm_uninstall $argv[2..-1]
        case update up
            __fpm_update $argv[2..-1]
        case list ls
            __fpm_list
        case search
            __fpm_search $argv[2..-1]
        case info
            __fpm_info $argv[2..-1]
        case upgrade self
            __fpm_upgrade_self
        case theme
            __fpm_theme $argv[2..-1]
        case clean
            __fpm_clean
        case status
            __fpm_status
        case export
            __fpm_export $argv[2..-1]
        case import
            __fpm_import $argv[2..-1]
        case pin
            __fpm_pin $argv[2..-1]
        case unpin
            __fpm_unpin $argv[2..-1]
        case outdated
            __fpm_outdated
        case doctor
            __fpm_doctor
        case init
            __fpm_init_plugin $argv[2..-1]
        case ''
            __fpm_help
        case '*'
            echo "Unknown command: $subcommand"
            __fpm_help
            return 1
    end
end

# ============================================
# Help System
# ============================================
function __fpm_help
    echo "Fish Plugin Manager (fpm) v$FPM_VERSION"
    echo ""
    echo "Commands:"
    echo "  install <plugin> [version]  Install a plugin"
    echo "  install <user/repo>        Install from GitHub"
    echo "  uninstall <plugin>         Remove a plugin"
    echo "  update [plugin]            Update plugins (or specific)"
    echo "  list                       List installed plugins"
    echo "  search <query>             Search for plugins"
    echo "  info <plugin>              Show plugin information"
    echo "  pin <plugin> <version>     Pin plugin to specific version"
    echo "  unpin <plugin>             Remove version pin"
    echo "  outdated                   Show outdated plugins"
    echo "  theme [set/list/install]   Theme management"
    echo "  clean                      Clean cache and temp files"
    echo "  status                     Show fpm status"
    echo "  export                     Export plugin list"
    echo "  import <file>              Import plugin list"
    echo "  init [plugin]              Initialize plugin template"
    echo "  doctor                     Diagnose issues"
    echo "  upgrade self               Upgrade fpm itself"
    echo "  help                       Show this help"
    echo ""
    echo "Options:"
    echo "  --verbose                  Show detailed output"
    echo "  --force                    Force operations"
    echo "  --no-cache                 Bypass cache"
    echo ""
    echo "Examples:"
    echo "  fpm install jethrokuan/z"
    echo "  fpm install oh-my-fish/plugin-vi-mode@v1.2.0"
    echo "  fpm theme install gruvbox"
    echo "  fpm pin z v2.0.0"
    echo "  fpm update --verbose"
end

# ============================================
# Enhanced Installation
# ============================================
function __fpm_install -a plugin ver
    set -l verbose false
    set -l force false
    set -l no_cache false

    # Parse options
    for arg in $argv
        switch $arg
            case --verbose
                set verbose true
            case --force
                set force true
            case --no-cache
                set no_cache true
        end
    end

    if test -z "$plugin"
        echo "Error: Plugin name required"
        return 1
    end

    # Parse plugin@version format
    if string match -q "*@*" $plugin
        set plugin (echo $plugin | cut -d@ -f1)
        set ver (echo $plugin | cut -d@ -f2)
    end

    # Check if already installed
    if __fpm_is_installed $plugin
        if test "$force" = false
            echo "Plugin '$plugin' is already installed"
            echo "Use --force to reinstall"
            return 0
        else
            __fpm_uninstall $plugin
        end
    end

    set -l plugin_name (basename $plugin)
    set -l install_path $FPM_PLUGINS/$plugin_name

    echo "Installing $plugin..."

    if string match -q "*/*" $plugin
        # GitHub repository installation
        set -l repo_url "https://github.com/$plugin.git"

        # Check if it's a theme
        if string match -q "*theme*" $plugin
            set install_path $FPM_THEMES/$plugin_name
        end

        git clone --depth 1 $repo_url $install_path ^/dev/null
        if test $status -eq 0
            # Handle version pinning
            if test -n "$ver"
                cd $install_path
                git fetch --tags
                git checkout $ver ^/dev/null
                cd - > /dev/null
                echo "Pinned to version: $ver"
            end

            # Add to plugin file
            if string match -q "*theme*" $plugin
                echo "theme:$plugin" >> $FPM_PLUGIN_FILE
            else
                echo "$plugin" >> $FPM_PLUGIN_FILE
            end

            echo "✓ Installed $plugin"

            # Run post-install hooks
            __fpm_run_hook $install_path "post-install"

            # Source plugin
            __fpm_source_plugin $plugin_name

            return 0
        else
            echo "✗ Failed to install $plugin"
            rm -rf $install_path
            return 1
        end
    else
        # Check registry for plugin
        set -l registry_entry (__fpm_query_registry $plugin)
        if test -n "$registry_entry"
            set -l repo (echo $registry_entry | jq -r '.repo')
            echo "Found in registry: $repo"
            __fpm_install $repo $ver
            return $status
        else
            echo "Error: Plugin '$plugin' not found in registry"
            echo "Use format 'user/repo' for GitHub plugins"
            return 1
        end
    end
end

# ============================================
# Plugin Registry
# ============================================
function __fpm_query_registry -a plugin_name
    # Build registry cache if not exists
    if not test -f $FPM_REGISTRY
        __fpm_build_registry
    end

    if test -f $FPM_REGISTRY
        jq -r ".[] | select(.name == \"$plugin_name\") | .repo" $FPM_REGISTRY 2>/dev/null
    end
end

function __fpm_build_registry
    echo "Building plugin registry..."
    # This would normally fetch from a central registry
    # For now, we'll create a local registry of popular plugins

    # Use echo with multiple lines instead of heredoc
    echo '[
  {"name": "z", "repo": "jethrokuan/z", "description": "Directory jumping", "category": "navigation"},
  {"name": "vi-mode", "repo": "oh-my-fish/plugin-vi-mode", "description": "Vi mode for fish", "category": "editing"},
  {"name": "fzf", "repo": "PatrickF1/fzf.fish", "description": "FZF integration", "category": "search"},
  {"name": "ghq", "repo": "decors/fish-ghq", "description": "GHQ integration", "category": "development"},
  {"name": "tide", "repo": "IlanCosman/tide", "description": "Modern prompt", "category": "theme"},
  {"name": "sponge", "repo": "meaningful-oss/sponge", "description": "Clean prompt", "category": "theme"},
  {"name": "pure", "repo": "pure-fish/pure", "description": "Pure prompt", "category": "theme"},
  {"name": "nvm", "repo": "jorgebucaran/nvm.fish", "description": "Node version manager", "category": "development"},
  {"name": "bass", "repo": "edc/bass", "description": "Bash compatibility", "category": "compatibility"},
  {"name": "done", "repo": "franciscolourenco/done", "description": "Notifications", "category": "utilities"}
]' > $FPM_REGISTRY

    echo "Registry built with 10 plugins"
end

function __fpm_search -a query
    if test -z "$query"
        echo "Error: Search query required"
        return 1
    end

    if not test -f $FPM_REGISTRY
        __fpm_build_registry
    end

    echo "Searching for: $query"
    echo ""

    # Search in registry
    jq -r ".[] | select(.name | contains(\"$query\")) | \"\\(.name) - \\(.repo)\n  \\(.description)\"" $FPM_REGISTRY 2>/dev/null

    # Also search installed plugins
    set -l installed (cat $FPM_PLUGIN_FILE 2>/dev/null)
    if test -n "$installed"
        set -l matches (string match -r ".*$query.*" $installed)
        if test -n "$matches"
            echo ""
            echo "Installed plugins matching:"
            for m in $matches
                echo "  ✓ $m (installed)"
            end
        end
    end
end

# ============================================
# Dependency Management
# ============================================
function __fpm_check_dependencies -a plugin_path
    set -l dep_file $plugin_path/fpm-deps.json

    if test -f $dep_file
        set -l deps (jq -r '.dependencies[]' $dep_file 2>/dev/null)

        if test -n "$deps"
            echo "Checking dependencies..."
            for dep in $deps
                if not __fpm_is_installed $dep
                    echo "  Installing dependency: $dep"
                    __fpm_install $dep
                else
                    echo "  ✓ $dep already installed"
                end
            end
        end
    end
end

# ============================================
# Version Pinning
# ============================================
function __fpm_pin -a plugin ver
    if test -z "$plugin" -o -z "$ver"
        echo "Usage: fpm pin <plugin> <version>"
        return 1
    end

    if not __fpm_is_installed $plugin
        echo "Plugin '$plugin' is not installed"
        return 1
    end

    set -l plugin_name (basename $plugin)
    set -l install_path $FPM_PLUGINS/$plugin_name

    cd $install_path
    git fetch --tags
    git checkout $ver ^/dev/null
    if test $status -eq 0
        echo "✓ Pinned $plugin to version $ver"
        echo "$plugin $ver" >> $FPM_HOME/pins.txt
    else
        echo "✗ Failed to pin $plugin to $ver"
        return 1
    end
    cd - > /dev/null
end

function __fpm_unpin -a plugin
    if test -z "$plugin"
        echo "Usage: fpm unpin <plugin>"
        return 1
    end

    if test -f $FPM_HOME/pins.txt
        sed -i.bak "/^$plugin /d" $FPM_HOME/pins.txt
        rm -f $FPM_HOME/pins.txt.bak
        echo "✓ Unpinned $plugin"
    end
end

function __fpm_get_pinned_version -a plugin
    if test -f $FPM_HOME/pins.txt
        grep "^$plugin " $FPM_HOME/pins.txt | cut -d' ' -f2
    end
end

# ============================================
# Outdated Plugin Check
# ============================================
function __fpm_outdated
    set -l plugins (cat $FPM_PLUGIN_FILE 2>/dev/null)

    if test -z "$plugins"
        echo "No plugins installed"
        return 0
    end

    echo "Checking for outdated plugins..."
    echo ""

    for p in $plugins
        set -l plugin_name (basename $p)
        set -l install_path $FPM_PLUGINS/$plugin_name

        if test -d "$install_path/.git"
            cd $install_path

            # Get current commit
            set -l current (git rev-parse HEAD)

            # Fetch latest
            git fetch origin master ^/dev/null

            # Get latest commit
            set -l latest (git rev-parse origin/master)

            if test "$current" != "$latest"
                set -l current_short (git rev-parse --short HEAD)
                set -l latest_short (git rev-parse --short origin/master)
                echo "  $p: $current_short -> $latest_short (update available)"
            else
                echo "  $p: ✓ up to date"
            end

            cd - > /dev/null
        end
    end
end

# ============================================
# Theme Management
# ============================================
function __fpm_theme -a action theme
    switch $action
        case list ls
            __fpm_theme_list
        case install i
            __fpm_theme_install $theme
        case set
            __fpm_theme_set $theme
        case remove rm uninstall
            __fpm_theme_remove $theme
        case ''
            echo "Theme commands:"
            echo "  fpm theme list            List installed themes"
            echo "  fpm theme install <theme> Install a theme"
            echo "  fpm theme set <theme>     Set active theme"
            echo "  fpm theme remove <theme>  Remove a theme"
        case '*'
            echo "Unknown theme command: $action"
    end
end

function __fpm_theme_list
    echo "Installed themes:"
    echo ""

    if test -d $FPM_THEMES
        for theme in (ls $FPM_THEMES)
            if test "$theme" = (__fpm_get_current_theme)
                echo "  ✓ $theme (active)"
            else
                echo "  $theme"
            end
        end
    end

    echo ""
    echo "Available themes to install:"
    echo "  tide, sponge, pure, gruvbox, dracula, nord"
end

function __fpm_theme_install -a theme
    if test -z "$theme"
        echo "Error: Theme name required"
        return 1
    end

    echo "Installing theme: $theme"

    # Map theme name to repo
    switch $theme
        case tide
            set repo "IlanCosman/tide"
        case sponge
            set repo "meaningful-oss/sponge"
        case pure
            set repo "pure-fish/pure"
        case gruvbox
            set repo "gmarmstrong/gruvbox-fish"
        case dracula
            set repo "dracula/fish"
        case nord
            set repo "nordtheme/fish"
        case '*'
            set repo $theme
    end

    __fpm_install $repo
    echo "Theme installed: $theme"
    echo "Use 'fpm theme set $theme' to activate"
end

function __fpm_theme_set -a theme
    if test -z "$theme"
        echo "Error: Theme name required"
        return 1
    end

    # Update config
    if test -f $FPM_CONFIG
        sed -i.bak "s/^set -g fpm_theme .*/set -g fpm_theme $theme/" $FPM_CONFIG
        rm -f $FPM_CONFIG.bak
    end

    echo "Theme set to: $theme"
    echo "Restart your shell or run 'source ~/.config/fish/config.fish' to apply"
end

function __fpm_theme_remove -a theme
    if test -z "$theme"
        echo "Error: Theme name required"
        return 1
    end

    if test -d $FPM_THEMES/$theme
        rm -rf $FPM_THEMES/$theme
        echo "✓ Removed theme: $theme"
    else
        echo "Theme '$theme' not found"
    end
end

function __fpm_get_current_theme
    grep "^set -g fpm_theme" $FPM_CONFIG 2>/dev/null | cut -d' ' -f3
end

# ============================================
# Plugin Hooks System
# ============================================
function __fpm_run_hook -a plugin_path hook_name
    set -l hook_file $plugin_path/hooks/$hook_name.fish

    if test -f $hook_file
        echo "Running hook: $hook_name"
        source $hook_file
    end
end

# ============================================
# Plugin Initialization Template
# ============================================
function __fpm_init_plugin -a plugin_name
    if test -z "$plugin_name"
        echo "Error: Plugin name required"
        return 1
    end

    set -l plugin_path $FPM_PLUGINS/$plugin_name

    if test -d $plugin_path
        echo "Error: Plugin already exists"
        return 1
    end

    mkdir -p $plugin_path/{functions,completions,conf.d,hooks,test}

    # Create init.fish - using echo instead of heredoc
    echo '# $plugin_name - Fish Plugin
# Initialize plugin

# Add functions
if test -d (dirname (status -f))/functions
    set -g fish_function_path (dirname (status -f))/functions $fish_function_path
end

# Add completions
if test -d (dirname (status -f))/completions
    set -g fish_complete_path (dirname (status -f))/completions $fish_complete_path
end

# Source configuration
if test -d (dirname (status -f))/conf.d
    for conf in (dirname (status -f))/conf.d/*.fish
        source $conf
    end
end

# Plugin initialization complete
echo "$plugin_name initialized"' > $plugin_path/init.fish

    # Create package file
    echo '{
  "name": "'$plugin_name'",
  "version": "0.1.0",
  "description": "A fish plugin",
  "author": "Your Name",
  "dependencies": [],
  "keywords": ["fish", "plugin"]
}' > $plugin_path/fpm.json

    # Create test file
    echo '#!/usr/bin/env fish
# Tests for '$plugin_name'

function test_plugin_loaded
    echo "Testing '$plugin_name'..."
    # Add your tests here
end

test_plugin_loaded' > $plugin_path/test/test.fish

    echo "✓ Created plugin template: $plugin_path"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $plugin_path/fpm.json"
    echo "  2. Add functions to $plugin_path/functions/"
    echo "  3. Write tests in $plugin_path/test/"
    echo "  4. Install with: fpm install $plugin_name (from local path)"
end

# ============================================
# Export/Import Plugin Lists
# ============================================
function __fpm_export
    set -l output_file $argv[1]

    if test -z "$output_file"
        set output_file "fpm-plugins.txt"
    end

    cp $FPM_PLUGIN_FILE $output_file
    echo "✓ Exported plugin list to: $output_file"
end

function __fpm_import -a input_file
    if test -z "$input_file"
        echo "Error: Input file required"
        return 1
    end

    if not test -f $input_file
        echo "Error: File not found: $input_file"
        return 1
    end

    echo "Importing plugins from: $input_file"

    while read -l plugin
        if test -n "$plugin" -a (string match -v '^#' $plugin)
            echo "Installing: $plugin"
            __fpm_install $plugin
        end
    end < $input_file

    echo "✓ Import complete"
end

# ============================================
# Doctor / Diagnostics
# ============================================
function __fpm_doctor
    echo "fpm Doctor - Diagnostic Report"
    echo "================================"
    echo ""

    # Check fish version
    echo "Fish version: "(fish --version)

    # Check directories
    echo ""
    echo "Directories:"
    for dir in FPM_HOME FPM_PLUGINS FPM_THEMES FPM_CACHE
        if test -d $$dir
            echo "  ✓ $dir: $$dir"
        else
            echo "  ✗ $dir: $$dir (missing)"
        end
    end

    # Check configuration
    echo ""
    echo "Configuration:"
    if test -f $FPM_CONFIG
        echo "  ✓ Config file: $FPM_CONFIG"
        echo "  Active theme: "(__fpm_get_current_theme)
    else
        echo "  ✗ Config file missing"
    end

    # Check installed plugins
    echo ""
    echo "Installed plugins: "(count (cat $FPM_PLUGIN_FILE 2>/dev/null))

    # Check dependencies
    echo ""
    echo "External dependencies:"
    for cmd in git curl jq
        if command -v $cmd > /dev/null
            echo "  ✓ $cmd"
        else
            echo "  ✗ $cmd (missing)"
        end
    end

    # Check permissions
    echo ""
    echo "Permissions:"
    if test -w $FPM_HOME
        echo "  ✓ FPM_HOME is writable"
    else
        echo "  ✗ FPM_HOME is not writable"
    end

    echo ""
    echo "Doctor check complete"
end

# ============================================
# Clean Command
# ============================================
function __fpm_clean
    echo "Cleaning fpm cache and temporary files..."

    if test -d $FPM_CACHE
        rm -rf $FPM_CACHE/*
        echo "✓ Cache cleaned"
    end

    # Remove backup files
    find $FPM_HOME -name "*.bak" -type f -delete 2>/dev/null
    echo "✓ Backup files removed"

    echo "Clean complete"
end

# ============================================
# Status Command
# ============================================
function __fpm_status
    echo "fpm Status"
    echo "=========="
    echo ""
    echo "Version: $FPM_VERSION"
    echo "Plugins installed: "(count (cat $FPM_PLUGIN_FILE 2>/dev/null))
    echo "Active theme: "(__fpm_get_current_theme)
    echo "Cache size: "(du -sh $FPM_CACHE 2>/dev/null | cut -f1)
    echo ""
    echo "Recently updated:"

    for p in (cat $FPM_PLUGIN_FILE 2>/dev/null | head -3)
        set -l plugin_name (basename $p)
        set -l install_path $FPM_PLUGINS/$plugin_name
        if test -d "$install_path/.git"
            set -l last_update (git -C $install_path log -1 --format=%cd --date=relative)
            echo "  $p: $last_update"
        end
    end
end

# ============================================
# Core Functions (Existing)
# ============================================
function __fpm_uninstall -a plugin
    if test -z "$plugin"
        echo "Error: Plugin name required"
        return 1
    end

    if not __fpm_is_installed $plugin
        echo "Plugin '$plugin' is not installed"
        return 1
    end

    set -l plugin_name (basename $plugin)
    set -l install_path $FPM_PLUGINS/$plugin_name

    # Run pre-uninstall hook
    __fpm_run_hook $install_path "pre-uninstall"

    echo "Uninstalling $plugin..."

    # Remove from plugins.txt
    sed -i.bak "/^$plugin\$/d" $FPM_PLUGIN_FILE
    rm -f $FPM_PLUGIN_FILE.bak

    # Remove plugin files
    rm -rf $install_path

    echo "✓ Uninstalled $plugin"
end

function __fpm_update -a plugin
    set -l verbose false

    for arg in $argv
        if test "$arg" = "--verbose"
            set verbose true
        end
    end

    if test -n "$plugin" -a (string match -v '^-' $plugin)
        # Update specific plugin
        if not __fpm_is_installed $plugin
            echo "Plugin '$plugin' is not installed"
            return 1
        end

        set -l plugin_name (basename $plugin)
        set -l install_path $FPM_PLUGINS/$plugin_name

        # Check if pinned
        set -l pinned_version (__fpm_get_pinned_version $plugin)
        if test -n "$pinned_version"
            echo "$plugin is pinned to version $pinned_version"
            echo "Use 'fpm unpin $plugin' to unpin"
            return 0
        end

        echo "Updating $plugin..."
        cd $install_path
        git pull --rebase

        if test $verbose = true
            git log -1 --oneline
        end

        cd - > /dev/null
        echo "✓ Updated $plugin"

        # Run post-update hook
        __fpm_run_hook $install_path "post-update"
    else
        # Update all plugins
        set -l plugins (cat $FPM_PLUGIN_FILE 2>/dev/null)
        if test -z "$plugins"
            echo "No plugins installed"
            return 0
        end

        echo "Updating all plugins..."
        for p in $plugins
            __fpm_update $p
        end
        echo "✓ All plugins updated"
    end
end

function __fpm_list
    set -l plugins (cat $FPM_PLUGIN_FILE 2>/dev/null)

    if test -z "$plugins"
        echo "No plugins installed"
        return 0
    end

    echo "Installed plugins:"
    echo ""

    for p in $plugins
        set -l plugin_name (basename $p)
        set -l install_path $FPM_PLUGINS/$plugin_name
        set -l is_theme (string match -q "theme:*" $p)

        # Check version
        if test -d "$install_path/.git"
            set -l ver (git -C $install_path rev-parse --short HEAD 2>/dev/null)
            set -l pinned (__fpm_get_pinned_version $p)

            if test -n "$pinned"
                echo "  $p (pinned: $pinned)"
            else if test -n "$is_theme"
                echo "  $p (theme)"
            else
                echo "  $p (v$ver)"
            end
        else
            echo "  $p"
        end
    end
end

function __fpm_info -a plugin
    if not __fpm_is_installed $plugin
        echo "Plugin '$plugin' is not installed"
        return 1
    end

    set -l plugin_name (basename $plugin)
    set -l install_path $FPM_PLUGINS/$plugin_name

    echo "Plugin: $plugin"
    echo "Location: $install_path"

    # Package info
    if test -f "$install_path/fpm.json"
        echo ""
        echo "Package info:"
        jq -r '. | "  Name: \(.name)\n  Version: \(.version)\n  Description: \(.description)\n  Author: \(.author)"' $install_path/fpm.json 2>/dev/null
    end

    if test -d "$install_path/.git"
        set -l branch (git -C $install_path branch --show-current)
        set -l commit (git -C $install_path rev-parse --short HEAD)
        set -l last_update (git -C $install_path log -1 --format=%cd)
        set -l pinned (__fpm_get_pinned_version $plugin)

        echo ""
        echo "Git info:"
        echo "  Branch: $branch"
        echo "  Commit: $commit"
        echo "  Last update: $last_update"
        if test -n "$pinned"
            echo "  Pinned: $pinned"
        end
    end

    # Show files
    echo ""
    echo "Contents:"
    if test -d "$install_path/functions"
        echo "  Functions: "(count (ls $install_path/functions/*.fish 2>/dev/null))
    end

    if test -d "$install_path/completions"
        echo "  Completions: "(count (ls $install_path/completions/*.fish 2>/dev/null))
    end

    if test -d "$install_path/conf.d"
        echo "  Config files: "(count (ls $install_path/conf.d/*.fish 2>/dev/null))
    end

    if test -d "$install_path/hooks"
        echo "  Hooks: "(count (ls $install_path/hooks/*.fish 2>/dev/null))
    end

    # Dependencies
    if test -f "$install_path/fpm-deps.json"
        set -l deps (jq -r '.dependencies[]' $install_path/fpm-deps.json 2>/dev/null)
        if test -n "$deps"
            echo ""
            echo "Dependencies:"
            for dep in $deps
                if __fpm_is_installed $dep
                    echo "  ✓ $dep"
                else
                    echo "  ✗ $dep (missing)"
                end
            end
        end
    end
end

function __fpm_source_plugin -a plugin_name
    set -l install_path $FPM_PLUGINS/$plugin_name

    # Source init files
    if test -f "$install_path/init.fish"
        source $install_path/init.fish             end
                                                   if test -f "$install_path/conf.d/$plugin_name.fish"
        source $install_path/conf.d/$plugin_name.fish
    end

    if test -f "$install_path/functions/init.fish"
        source $install_path/functions/init.fish                                                  end

    # Add to paths
    if test -d "$install_path/functions"
        set -g fish_function_path $install_path/functions $fish_function_path
    end

    if test -d "$install_path/completions"
        set -g fish_complete_path $install_path/completions $fish_complete_path
    end
end

function __fpm_is_installed -a plugin
    grep -qxF "$plugin" $FPM_PLUGIN_FILE ^/dev/null
    return $status
end

function __fpm_upgrade_self
    echo "Upgrading fpm..."

    set -l fpm_path (status -f)
    set -l tmp_file (mktemp)

    curl -sL "https://raw.githubusercontent.com/yourusername/fpm/main/fpm.fish" -o $tmp_file

    if test $status -eq 0 -a -s $tmp_file
        mv $tmp_file $fpm_path
        chmod +x $fpm_path
        echo "✓ fpm upgraded successfully to v$FPM_VERSION"
    else
        echo "✗ Failed to upgrade fpm"
        rm -f $tmp_file
        return 1
    end
end

# ============================================
# Initialize Plugins
# ============================================
function __fpm_init
    if test -f $FPM_PLUGIN_FILE
        for plugin in (cat $FPM_PLUGIN_FILE)               set -l plugin_name (basename $plugin)
            __fpm_source_plugin $plugin_name
        end                                        end
                                                   # Apply theme
    set -l theme (__fpm_get_current_theme)
    if test -n "$theme" -a -d $FPM_THEMES/$theme
        __fpm_source_plugin $theme
    end
end

# ============================================
# Completions
# ============================================
complete -c fpm -f
complete -c fpm -n "__fish_use_subcommand" -a help -d "Show help"
complete -c fpm -n "__fish_use_subcommand" -a install -d "Install plugin"
complete -c fpm -n "__fish_use_subcommand" -a uninstall -d "Uninstall plugin"
complete -c fpm -n "__fish_use_subcommand" -a update -d "Update plugins"
complete -c fpm -n "__fish_use_subcommand" -a list -d "List plugins"
complete -c fpm -n "__fish_use_subcommand" -a search -d "Search plugins"
complete -c fpm -n "__fish_use_subcommand" -a info -d "Show plugin info"                      complete -c fpm -n "__fish_use_subcommand" -a upgrade -d "Upgrade fpm"                        complete -c fpm -n "__fish_use_subcommand" -a theme -d "Theme management"
complete -c fpm -n "__fish_use_subcommand" -a clean -d "Clean cache"
complete -c fpm -n "__fish_use_subcommand" -a status -d "Show status"
complete -c fpm -n "__fish_use_subcommand" -a export -d "Export plugins"
complete -c fpm -n "__fish_use_subcommand" -a import -d "Import plugins"
complete -c fpm -n "__fish_use_subcommand" -a pin -d "Pin plugin version"
complete -c fpm -n "__fish_use_subcommand" -a unpin -d "Unpin plugin"
complete -c fpm -n "__fish_use_subcommand" -a outdated -d "Check outdated"
complete -c fpm -n "__fish_use_subcommand" -a doctor -d "Diagnose issues"
complete -c fpm -n "__fish_use_subcommand" -a init -d "Initialize plugin"

# Complete installed plugins
complete -c fpm -n "__fish_seen_subcommand_from uninstall update info pin unpin" -a "(cat $FPM_PLUGIN_FILE 2>/dev/null)" -d "Installed plugin"

# Complete theme commands
complete -c fpm -n "__fish_seen_subcommand_from theme" -a list -d "List themes"
complete -c fpm -n "__fish_seen_subcommand_from theme" -a install -d "Install theme"
complete -c fpm -n "__fish_seen_subcommand_from theme" -a set -d "Set theme"
complete -c fpm -n "__fish_seen_subcommand_from theme" -a remove -d "Remove theme"

# ============================================
# Run Initialization
# ============================================
__fpm_init

# ============================================
# End of fpm.fish
# ============================================