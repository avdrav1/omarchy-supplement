# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Repository purpose

This repository contains shell scripts and configuration to supplement an Omarchy-based development environment on Arch Linux. Its primary role is to automate installation and configuration of core tools (shell, version managers, runtimes, database, terminals, editors/UI), as well as Hyprland and theme overrides, on a new or existing system.

There is no application build, packaging, or test pipeline here; the "units" of work are the installer scripts themselves.

## Key commands

All commands below assume you are in the repository root.

### Install everything (recommended path)

- Run the full environment setup in the intended order:
  - `./install-all.sh`

`install-all.sh` orchestrates the individual installers in a safe order (shell and tooling first, then runtimes, apps, dotfiles, Hyprland overrides, and finally theme integration). Use this script when provisioning a fresh machine to get the full Omarchy supplement setup.

### Run individual installers

Each `install-*.sh` script is idempotent-ish and targets a single concern. Common examples:

- Shell and tooling
  - `./install-zsh.sh` – install Zsh via `yay`, Oh My Zsh, core Zsh plugins, and the Starship prompt.
  - `./set-shell.sh` – make Zsh the default login shell (adds it to `/etc/shells` if needed and runs `chsh`).
  - `./install-mise.sh` – install the `mise` tool/version manager into `~/.local/bin` via its official install script.
  - `./install-asdf.sh` – install `asdf-vm` from the AUR via `yay`.
  - `./install-stow.sh` – install GNU Stow via `yay` (used by the dotfiles installer).

- Language runtimes and database (via `asdf` and system services)
  - `./install-nodejs.sh` – ensure `asdf` is present, install Node.js build deps via `yay`, add the `asdf-nodejs` plugin, and install/set a `latest:20` Node.js.
  - `./install-ruby.sh` – ensure `asdf` is present, install Ruby build deps via `yay`, add the `asdf-ruby` plugin, and install/set the latest Ruby.
  - `./install-postgresql.sh` – install PostgreSQL via `yay`, initialize the data directory if needed, start and enable the `postgresql` systemd service, and create a database user + database matching `$USER` if missing.

- Applications and terminals
  - `./install-ghostty.sh` – install the Ghostty terminal (see script for exact package details).
  - `./install-warp-terminal.sh` – add the `warpdotdev` pacman repo if missing, import/sign its key, and install `warp-terminal` via `pacman`.
  - `./install-tmux.sh`, `./install-github-desktop.sh`, `./install-claude-code.sh`, `./install-claude-desktop.sh`, `./install-kiro-ide.sh`, `./install-kiro-cli.sh` – install various development tools and editors (check each script for specifics; all are Arch/AUR-focused and use `yay`/`pacman`).

- Dotfiles and desktop/theme integration
  - `./install-dotfiles.sh` – clone `https://github.com/avdrav1/dotfiles` into `~/dotfiles` if missing, remove a set of existing config directories, and `stow` profiles for Zsh, Ghostty, tmux, Neovim, and Starship.
  - `./install-hyprland-overrides.sh` – ensure `~/.config/hypr/hyprland.conf` exists, then append a `source = <repo>/hyprland-overrides.conf` line if it is not already present.
  - `./install-theme.sh` – install the Omarchy Miasma theme via `omarchy-theme-install`, then copy the theme's Waybar `config.jsonc` and `style.css` into both `~/dotfiles/waybar/.config/waybar` and `~/.config/waybar`, and finally call `omarchy-restart-waybar`.

### Notes on running and verifying scripts

- All scripts assume an Arch Linux system with the `yay` AUR helper installed and `systemctl` available.
- Most scripts are safe to re-run; they check for existing installations (e.g., `command -v`, `asdf plugin list`, presence of initialized PostgreSQL data) before doing work.
- There is no automated test suite; to validate changes, run the affected installer script on a test machine or container and verify side effects (e.g., `command -v zsh`, `asdf list nodejs`, `psql` connectivity, Hyprland keybindings).

## Architecture and structure

### Top-level layout

- Root directory contains:
  - A collection of `install-*.sh` scripts, each responsible for provisioning or configuring a single tool or subsystem.
  - `install-all.sh` as the main orchestration entrypoint, sequencing the installers in a dependency-aware order.
  - `hyprland-overrides.conf` with Hyprland-specific keybindings, monitor settings, and input tweaks.
  - `.claude/settings.local.json` containing Claude-specific permissions (no additional coding rules are defined here).

There are no nested modules or libraries; logic lives directly in the shell scripts.

### Installer orchestration

`install-all.sh` wires together the individual installers and encodes their implicit dependencies:

1. Shell and core CLI tooling: Zsh, `mise`, `asdf`, Node.js, Ruby, PostgreSQL.
2. Graphical tools and terminals: Ghostty, tmux, GitHub Desktop, Claude integrations, Warp terminal, Kiro IDE/CLI.
3. Configuration layering: install Stow, then dotfiles, then Hyprland overrides.
4. Final polish: set Zsh as the default shell and apply Omarchy Miasma theme integration.

Future modifications to the environment should respect this layering: ensure any new installer script can be run independently, and only then add it to `install-all.sh` in an order that satisfies its dependencies (e.g., after its package manager or runtime is installed).

### Hyprland and desktop overrides

`hyprland-overrides.conf` is sourced into the user's main Hyprland config via `install-hyprland-overrides.sh`. It:

- Defines `$terminal` as `uwsm app -- ghostty` and `$browser` as Chromium with a custom scale factor.
- Forces a single default monitor configuration and binds lid switch events to enabling/disabling the laptop display.
- Rebinds several `SUPER`-based keybindings to use Omarchy-style semantics:
  - SUPER+SHIFT+D/F to toggle the internal monitor.
  - SUPER+D/G to launch Discord/Notion as web apps via `omarchy-launch-webapp`.
  - SUPER+RETURN to always open the configured `$terminal` (Ghostty) and SUPER+B to open `$browser`.
  - SUPER+h/j/k/l to move focus, instead of Hyprland's default bindings.
- Tweaks `misc` and `input` blocks, notably keyboard repeat rate/delay and touchpad scroll behavior.

When adjusting Hyprland behavior, prefer editing `hyprland-overrides.conf` rather than the main Hyprland config so that this repository remains the single source of truth for Omarchy-specific overrides.

### External dependencies and assumptions

- System: Arch Linux (scripts rely on `pacman`, `yay`, and `systemctl`).
- Shell: Bash for script execution; target default shell is Zsh.
- External Omarchy tooling: `omarchy-theme-install`, `omarchy-restart-waybar`, and `omarchy-launch-webapp` are assumed to be available from the broader Omarchy setup and are not defined in this repo.
- Dotfiles: expects the `avdrav1/dotfiles` repository layout to remain compatible with the `stow` calls in `install-dotfiles.sh` and the Waybar paths in `install-theme.sh`.

### Other agent rule sources

- There is no `CLAUDE.md`, `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` file in this repository.
- Aside from this `WARP.md` file and the minimal `.claude/settings.local.json` permissions, there are no additional agent-specific rule documents to mirror.
