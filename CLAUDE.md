# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Shell scripts and config that supplement an [Omarchy](https://omarchy.org/)
(Arch Linux + Hyprland) environment. There is **no application, build, or test
pipeline** — the units of work are the `install-*.sh` scripts themselves. To
"test" a change, run the affected installer on a real machine/container and
verify its side effects (`command -v <tool>`, `asdf list`, `psql` connectivity,
`hyprctl reload`, etc.).

`WARP.md` holds the full per-script reference and architecture; `README.md`
documents the per-machine display-scaling workflow. Read those before deep work
in their respective areas.

## Commands

- `./install-all.sh` — provision a full machine. It `cd`s to its own dir first,
  then runs the individual installers in dependency order (shell/tooling →
  runtimes/db → apps → stow/dotfiles/hyprland overrides → set-shell → theme).
- `./install-<concern>.sh` — run a single installer. Each targets one concern
  and is written to be re-runnable (guards with `command -v`, `pacman -Qi`,
  `asdf plugin list`, presence checks before acting).

## Conventions to follow

- **Arch-only assumptions:** scripts rely on `yay`/`pacman` and `systemctl`.
  Omarchy commands (e.g. `omarchy-launch-webapp`) are assumed present from the
  broader Omarchy install and are not defined here.
- **Adding an installer:** make it independently runnable first, then insert it
  into `install-all.sh` at a position that satisfies its dependencies (after the
  package manager / runtime it needs).
- **Hyprland changes go in this repo**, not the main Hyprland config, making it
  the single source of truth for Omarchy overrides. Omarchy migrated Hyprland
  config from hyprlang (`.conf`) to **Lua**, so two parallel trees exist while
  the fleet is mid-migration:

  | Parser | Overrides | Per-host scale | Entry point |
  |---|---|---|---|
  | Lua (current) | `hypr/lua/*.lua` | `hypr/lua/hosts/<hostname>.lua` | `require("supplement.init")` in `~/.config/hypr/hyprland.lua` |
  | hyprlang (legacy) | `hyprland-overrides.conf` | `hosts/<hostname>.conf` | `source = …` in `~/.config/hypr/hyprland.conf` |

  `install-hyprland-overrides.sh` detects which the machine uses (Lua when
  `~/.config/hypr/hyprland.lua` exists) and installs only that one. For Lua it
  symlinks `~/.config/supplement` → `hypr/lua/` — Hyprland's `package.path`
  already covers `~/.config/?.lua`. Either way the overrides load **last**, so
  they beat omarchy-managed config like `monitors.lua`/`monitors.conf`.
  **Changes must be made in both trees** until every machine has migrated.
- **Writing Lua config:** the `hl` (Hyprland) and `o` (Omarchy helpers) globals
  are already in scope. Authoritative API reference is the shipped stub
  `/usr/share/hypr/stubs/hl.meta.lua`; Omarchy's helpers are in
  `/usr/share/omarchy/default/hypr/helpers.lua` (`o.bind`, `o.window`,
  `o.exec_on_start`, …). Traps, all of which fail *silently*:
  - `hl.bind` *adds* a bind rather than replacing one, so reusing an Omarchy
    default key needs `hl.unbind` first.
  - `hyprctl keyword` and `hyprctl dispatch <legacy-name>` **do not work at
    all** — `hyprctl dispatch` evaluates Lua, so use
    `hyprctl dispatch 'hl.dsp.exec_cmd("…")'`. This also means plugins are
    reachable only via their Lua namespace (`hl.plugin.<ns>.*`), never their
    `plugin:dispatcher` names.
  - `require()` caches, and Hyprland's `bootstrap.lua` clears `package.loaded`
    only for its own prefixes (`default.hypr`, `hypr`, `omarchy.current.theme`).
    A `supplement.*` module would therefore load once and never re-run on
    reload. `hyprland.lua` reaches `init.lua` via `dofile` (always re-executes)
    and `init.lua` clears the `supplement.` cache itself.
- **Display scale is per-machine, never hardcoded in shared config.** Each
  machine's scale lives in a tracked host file (`hypr/lua/hosts/<hostname>.lua`
  returning `{ scale, gdk_scale }`, or legacy `hosts/<hostname>.conf` defining
  `$MONSCALE`). To change a machine's scale, edit its host file, re-run
  `./install-hyprland-overrides.sh`, `hyprctl reload`, and commit.
- **Scale is the one setting the supplement does NOT own via `hl.monitor`.**
  Omarchy's `omarchy-hyprland-monitor-watch` daemon polls every 2 seconds and
  force-reapplies the internal display's scale, parsing it out of
  `~/.config/hypr/monitors.lua` with
  `sed -n 's/^local omarchy_monitor_scale = //p'` and falling back to a
  **hardcoded 2** when that isn't a bare number — which the stock `= "auto"`
  triggers. Any `hl.monitor` rule set elsewhere is reverted within seconds, so
  `install-hyprland-overrides.sh` *generates* `~/.config/hypr/monitors.lua` from
  the host file instead, preserving that exact line format. When debugging
  scale, check that file and the daemon before the Lua modules. Allow ~5s after
  a reload before reading `hyprctl monitors` — the poll can return a stale value.
- **Dotfiles** come from the external `avdrav1/dotfiles` repo via GNU Stow
  (`install-dotfiles.sh`). It `rm -rf`s a fixed set of existing configs before
  stowing — keep that removal list in sync with the stow targets.
