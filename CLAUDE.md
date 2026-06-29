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
- **Hyprland changes go in `hyprland-overrides.conf`**, not the main Hyprland
  config. `install-hyprland-overrides.sh` appends a `source = <repo>/hyprland-overrides.conf`
  line to `~/.config/hypr/hyprland.conf`, making this repo the single source of
  truth for Omarchy overrides. It is sourced *last*, so it overrides
  omarchy-managed configs like `monitors.conf`.
- **Display scale is per-machine, never hardcoded in shared config.**
  `hyprland-overrides.conf` sources `~/.config/hypr/monitors.local.conf`, a
  symlink to a tracked `hosts/<hostname>.conf` that defines `$MONSCALE` plus the
  monitor/GDK lines. `install-hyprland-overrides.sh` picks `hosts/$(hostname).conf`,
  seeding it from `hosts/default.conf` if absent, then symlinks to it. To change
  a machine's scale, edit its `hosts/<hostname>.conf`, `hyprctl reload`, and
  commit. Because every host's intended scale lives in `hosts/`, you can inspect
  or fix any machine's scaling from any checkout — no SSH needed. See `README.md`.
- **Dotfiles** come from the external `avdrav1/dotfiles` repo via GNU Stow
  (`install-dotfiles.sh`). It `rm -rf`s a fixed set of existing configs before
  stowing — keep that removal list in sync with the stow targets.
