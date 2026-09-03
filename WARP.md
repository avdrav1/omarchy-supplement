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
  - `./install-tmux.sh`, `./install-github-desktop.sh`, `./install-claude-code.sh`, `./install-kiro-ide.sh`, `./install-kiro-cli.sh` – install various development tools and editors (check each script for specifics; all are Arch/AUR-focused and use `yay`/`pacman`).
  - `./install-vscode.sh` – install the official Microsoft VS Code build `visual-studio-code-bin` from the AUR via `yay` (guarded by `pacman -Qi`). Its tracked config is stowed by `install-dotfiles.sh` (the `vscode` profile) into `~/.config/Code/User/`.
  - `./install-obsidian.sh` – install Obsidian from the Arch `extra` repo via `pacman` (guarded by `pacman -Qi`). No dotfiles profile: Obsidian's settings live per-vault in each vault's `.obsidian/` folder, not in `~/.config`.
  - `./install-slack.sh` – install Slack Desktop (`slack-desktop`) from the AUR via `yay` (guarded by `pacman -Qi`). No dotfiles profile: Slack's config lives in `~/.config/Slack` and holds per-machine secrets. Sign in on first launch.
  - `./install-strata.sh` – install **Strata** (`https://github.com/lgse/strata`), a keyboard-first Miller-column file manager (Rust/GTK4), and make it the desktop's file manager. **Not in the AUR** — upstream ships precompiled per-arch tarballs on GitHub Releases, so this installer resolves the latest tag from the API, downloads the matching `x86_64`/`aarch64` build into a `mktemp -d`, and installs the binary to `~/.local/bin/strata`. Verification is two-tier: the SHA-256 is **fatal** on mismatch, while `gh attestation verify --repo lgse/strata` (signed GitHub Actions provenance) is **skipped with a warning** when `gh` is absent or unauthenticated — true on a from-scratch provision, since `gh` arrives via mise — but **fatal when `gh` is present and the check fails**. Runtime deps (`bubblewrap ffmpeg ffmpegthumbnailer fontconfig gst-libav gst-plugins-good gtk4 gtksourceview5 gvfs-smb poppler-glib`, all official-repo, so `pacman` not `yay`) are guarded as a set so a provisioned machine touches no sudo — the GStreamer pair backs video previews and `gvfs-smb` the `Ctrl+L` `smb://` path; both were added to upstream's dependency list after 0.4.0, and their absence degrades *silently* rather than failing at startup. The script also generates `~/.local/share/applications/io.github.lgse.Strata.desktop` (with `Exec=strata %U` — the bare name, so the entry stays host-independent) and runs `xdg-mime default … inode/directory`, which is what makes Strata the folder handler for *every* machine, legacy trees included. **Re-run detection uses a version stamp** at `~/.local/share/strata/installed-version`: upstream ships no `--version` flag (`strata --version` prints `Unknown option`), so there is nothing on the binary to interrogate; a missing stamp reinstalls. Offline runs are non-fatal when Strata is already present. **Config is seeded, never stowed.** 0.7.0 added `~/.config/strata/settings.toml` (and custom palettes in `~/.config/strata/themes/`), so `strata/settings.toml` in this repo is copied into place **as a real file when absent** and thereafter owned by the app — a re-run never discards changes made in Settings (`Ctrl+,`), and a symlink is reported rather than repaired. It must not be a symlink: Strata saves through `storage::atomic_write`, which stats the destination with `symlink_metadata` and rejects anything that is not a regular file (upstream's own test is `symlink_destination_is_rejected_without_touching_target`, on a destination literally named `settings.toml`). A stow symlink would neither be followed nor replaced — every preference change would fail into a `tracing::warn` the UI never surfaces and be lost on restart. Hence its absence from `install-dotfiles.sh`, for a *stronger* reason than `starship.toml`'s. The seeded file sets `mode = "omarchy"` so Strata tracks the active Omarchy theme via `~/.local/state/omarchy/current/` (Quattro only) and restyles when `install-theme.sh` runs — explicit because Strata auto-selects that mode *only* while no settings file exists at all. No custom theme ships, since following Omarchy makes a checked-in copy pure drift. It also sets `check_for_updates = false`: 0.7.0's in-app updater writes the binary behind the version stamp's back, and on a prerelease channel would leave the next run **downgrading** the machine, since the `releases/latest` endpoint this script reads excludes prereleases. Keybindings are **Lua-tree only** (see `hypr/lua/bindings.lua` and the divergence note in `hyprland-overrides.conf`).
  - `./install-claude-desktop.sh` – install or update (to the latest) Anthropic's official Linux Claude Desktop, `claude-desktop` from the AUR, via `yay -S --needed`. Ships Chat, Cowork, and Claude Code natively. Removes the superseded third-party builds if present (`claude-desktop-bin`, older aaddrick `claude-desktop-debug`); user config in `~/.config/Claude` is preserved.

- Dotfiles and desktop/theme integration
  - `./install-dotfiles.sh` – clone `https://github.com/avdrav1/dotfiles` into `~/dotfiles` if missing, remove a set of existing config directories, and `stow` profiles for Zsh, Ghostty, tmux, Neovim, Starship, snappy-switcher, aerc-mail, and VS Code (`vscode` – `mkdir -p ~/.config/Code/User` first so only `settings.json`/`keybindings.json` are symlinked, not the whole `Code` dir). Waybar excluded since the Quickshell-based bar (Shibumi) replaces it.
  - `./install-hyprland-overrides.sh` – ensure `~/.config/hypr/hyprland.conf` exists, then append a `source = <repo>/hyprland-overrides.conf` line if it is not already present.
  - `./install-hyprland-scroll-overview.sh` – install `hyprland-scroll-overview` (touchpad-scroll workspace overview) as the hyprpm plugin `scrolloverview` from `https://github.com/yayuuu/hyprland-scroll-overview`, enable it, `hyprpm reload` it into a running session, and drop `hypr/hyprpm-plugins.hook` into `/etc/pacman.d/hooks/`. **hyprpm plugins are version-locked to the installed Hyprland**: they are compiled against its headers, so after every Hyprland upgrade the plugin silently stops loading (`SUPER+\`` does nothing; `hyprctl configerrors` reports `Invalid dispatcher, requested "scrolloverview:overview" does not exist`) until `hyprpm update && hyprpm reload` is run. The pacman hook only *prints that reminder* post-upgrade — it cannot do the rebuild, because `hyprpm` elevates via sudo internally to write its root-owned state under `/var/cache/hyprpm/$USER` and a hook has no tty for the prompt. All Hyprland wiring (the `plugin{}` block, `SUPER+grave`, the `scrolloverview` submap, and the `ALT+1..9` `bindu` lines) lives at the **end** of `hyprland-overrides.conf`; nothing for this plugin ships via the dotfiles repo.
  - `./install-theme.sh` – apply the Dos-Moos Omarchy theme (`https://github.com/HANCORE-linux/omarchy-dos-moos-theme`) and restart snappy-switcher so it picks up its themed config. No bar work happens here any more: the Quickshell Rise bar this script used to install has been superseded by Shibumi Shell (see `install-shibumi.sh`).
  - `./install-shibumi.sh` – install **Shibumi Shell** (HANCORE-linux's native bar and plugin suite for Omarchy Quattro) from source, and retire the older Quickshell Rise bar it supersedes. **Requires Omarchy 4 (quattro) and Quickshell 0.3.0+** — the suite refuses to run otherwise. Unlike Rise (a standalone `qs` instance launched by an Omarchy post-boot hook out of `~/.config/quickshell/bar`), Shibumi installs as ~24 Omarchy plugins under `~/.config/omarchy/plugins` and edits `~/.config/omarchy/shell.json`, so it runs **inside** the stock `omarchy-shell` process. The script installs the runtime deps its widgets need (`python jq curl networkmanager power-profiles-daemon upower xdg-utils libnotify wl-clipboard` + Material Symbols / JetBrainsMono-Nerd-basic / Noto CJK / Adwaita fonts, only the missing ones so a re-run touches no sudo), clones the upstream repo to `~/.local/share/Shibumi-Shell`, and runs its transactional CLI: `scripts/shibumi-suite install --yes` on first run, `update --yes` thereafter (detected via `shibumi-suite status`). It then tears down the Rise footprint (the `post-boot.d/quickshell-rise` and `theme-set.d/50-quickshell-bar.sh` hooks, `~/.config/quickshell/{bar,bin}`, the `qs-shell-update-check` systemd user units and the transient `qsrise-bar-*` scope, and `~/.local/state/quickshell-rise`), turns the stock omarchy bar back on (`omarchy-toggle-bar on`, which Rise had toggled off), and restarts the shell. The `*-usage.service` collectors are left alone — Shibumi's `hancore.shibumi.ai` plugin consumes the same data. Reversible via `shibumi-suite uninstall --yes`. Update later with `git -C ~/.local/share/Shibumi-Shell pull --ff-only && ~/.local/share/Shibumi-Shell/scripts/shibumi-suite update --yes`.
  - `./install-omarchy-menu-websearch.sh` – make the Omarchy menu (SUPER+SPACE) offer a **web search** when a query matches no menu row and no installed app, instead of its dead "No matches for …" card. Enter on that row runs `omarchy-launch-browser` with the query. **Requires Omarchy 4 (quattro).** The menu's search is a pure filter over menu items + `.desktop` entries with no fallback hook — `~/.config/omarchy/extensions/omarchy-menu.jsonc` can only *add* rows (subject to the same all-terms-must-match filter) and `provider` rows are limited to the provider names hardcoded in `Menu.qml` — so the only way in is to edit `Menu.qml`. The script therefore clones the first-party `omarchy.menu` plugin to `~/.config/omarchy/plugins/<user>.menu` (the manifest's `omarchy.clonedFrom` is what makes the shell route existing `omarchy.menu` IPC and keybindings to the clone) and applies two small anchored hunks: a `webSearchRow()` helper next to `runAction()`, and a `if (rows.length === 0) rows.push(...)` line at the end of `rebuildDisplay()`'s search branch. **Nothing is vendored in this repo** — each run re-clones from whatever `/usr/share/omarchy` currently ships and re-patches on top, so **re-run it after `omarchy update`** to resync; if upstream moves an anchor the run fails loudly rather than silently no-opping. Idempotent (it strips its own hunks before re-applying — a bare re-apply would duplicate the QML declarations and take the whole menu plugin down). Search engine is overridable per machine via `OMARCHY_MENU_SEARCH_URL` / `OMARCHY_MENU_SEARCH_LABEL`. Revert with `./install-omarchy-menu-websearch.sh --uninstall`.
    Two Omarchy behaviours this script exists to work around, worth knowing when debugging it: (1) a plugin's QML is compiled once and cached, so saving `Menu.qml` logs `Local plugin changed, reloading` and `rescanPlugins` returns fine but **neither re-executes the new code** — only `omarchy restart shell` does; (2) `omarchy plugin enable` on a plugin that also declares a `bar-widget` kind (the menu does) enables it *by placing it in the bar*, adding an unwanted launcher button. This script instead references the clone in shell.json's `plugins[]` and disables the built-in via `disabledPlugins[]`, which turns the component on without touching `bar.layout`.

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
2. Graphical tools and terminals: Ghostty, tmux, GitHub Desktop, Claude integrations (Claude Code, Claude Desktop), Warp terminal, Kiro IDE/CLI.
3. Configuration layering: install Stow, then dotfiles, then Hyprland overrides.
4. Final polish: set Zsh as the default shell, apply the Dos-Moos theme, then install the Shibumi Shell bar/plugin suite (which replaces waybar and retires the older Quickshell Rise bar).

Future modifications to the environment should respect this layering: ensure any new installer script can be run independently, and only then add it to `install-all.sh` in an order that satisfies its dependencies (e.g., after its package manager or runtime is installed).

### Hyprland and desktop overrides

`hyprland-overrides.conf` is sourced into the user's main Hyprland config via `install-hyprland-overrides.sh`. It:

- Defines `$terminal` as `uwsm app -- ghostty` and `$browser` as Chromium with a custom scale factor.
- Forces a single default monitor configuration and binds lid switch events to enabling/disabling the laptop display.
- Rebinds several `SUPER`-based keybindings to use Omarchy-style semantics:
  - SUPER+SHIFT+D/F to toggle the internal monitor.
    - **The one intentional divergence between the two config trees.** `hypr/lua/bindings.lua` binds SUPER+SHIFT+F to the Strata file manager (replacing Omarchy's Nautilus default), but that key is the eDP-1 re-enable bind here — and hyprlang `bind` *adds* rather than replaces, so binding Strata in both trees would fire the monitor command **and** launch Strata on one press. Legacy (hyprlang) machines therefore keep the stock Nautilus binds; `install-strata.sh` still sets the `inode/directory` handler on them, so folders opened from other apps use Strata regardless. Fold the trees back together if the display binds ever move off SUPER+SHIFT+F.
  - SUPER+D/G to launch Discord/Notion as web apps via `omarchy-launch-webapp`.
  - SUPER+RETURN to always open the configured `$terminal` (Ghostty) and SUPER+B to open `$browser`.
  - SUPER+h/j/k/l to move focus, instead of Hyprland's default bindings.
- Tweaks `misc` and `input` blocks, notably keyboard repeat rate/delay and touchpad scroll behavior.

When adjusting Hyprland behavior, prefer editing `hyprland-overrides.conf` rather than the main Hyprland config so that this repository remains the single source of truth for Omarchy-specific overrides.

**Add new binds ABOVE the `scrolloverview` block at the end of `hyprland-overrides.conf`.** That block contains a `submap = scrolloverview` … `submap = reset` pair, and everything between those two lines belongs to the submap. A bind appended after `submap = scrolloverview` but before `submap = reset` is only live while the overview is open, and would appear to "do nothing" globally — with no error from `hyprctl configerrors`.

### External dependencies and assumptions

- System: Arch Linux (scripts rely on `pacman`, `yay`, and `systemctl`).
- Shell: Bash for script execution; target default shell is Zsh.
- External Omarchy tooling: `omarchy-launch-webapp` and other Omarchy commands are assumed to be available from the broader Omarchy setup and are not defined in this repo.
- Dotfiles: expects the `avdrav1/dotfiles` repository layout to remain compatible with the `stow` calls in `install-dotfiles.sh`.
- Shibumi Shell: `install-shibumi.sh` clones `https://github.com/HANCORE-linux/Shibumi-Shell` to `~/.local/share/Shibumi-Shell` and installs its suite as Omarchy plugins under `~/.config/omarchy/plugins` (+ `~/.config/omarchy/shell.json`). It supersedes the former Quickshell Rise bar (`quickshell-dots`, `~/.config/quickshell/bar`), which the same script removes.

### Other agent rule sources

- There is no `CLAUDE.md`, `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` file in this repository.
- Aside from this `WARP.md` file and the minimal `.claude/settings.local.json` permissions, there are no additional agent-specific rule documents to mirror.
