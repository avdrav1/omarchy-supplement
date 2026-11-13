# CLAUDE.md

Guidance for Claude Code when working in this repo. Read `README.md` first for
the layout.

## What this repo is

Bash modules and config that provision a fresh Omarchy (Arch + Hyprland, Lua
config) machine. There is no build or test suite: to test a change, run the
module (`./setup <name>`, or `bash modules/NN-name.sh` when no sudo is needed)
and check its side effects. Every other machine is set up from a **fresh**
Omarchy install, so don't add code that migrates old setups.

The alienware host is the reference machine. Something set up there by hand (an
app, bind, theme) only reaches other machines once it's added here. Shibumi is
the only Omarchy shell plugin on these machines; don't add third-party widgets
or shell plugins without being asked.

## Conventions

- **Lists over scripts.** A new app is a line in `manifest/`; a new
  module is only for something that needs real logic.
- **Don't duplicate Omarchy.** Check `/usr/share/omarchy/install/*.packages`,
  `/etc/mise/conf.d/omarchy-tools.toml` and `omarchy install --help` before
  adding anything. Prefer `omarchy install ...` (manifest/omarchy.txt) over a
  bare package when Omarchy has an installer.
- **Modules** start with `#!/bin/bash`, a one-line description on line 2 (shown
  by `./setup --list`), then `source "$(dirname "$0")/../lib/common.sh"`. That
  gives `set -euo pipefail`, Omarchy's bin dir on PATH, `$REPO $CONFIG $ASSETS
  $MANIFEST $SHELL_JSON $PLUGINS_DIR`, and the helpers. Don't reuse those names.
- **Idempotent and quiet when done:** check before acting, and never reach for
  sudo when nothing is missing (`pkg` filters installed packages first; `put`
  skips identical files).
- **Settings an app rewrites on save** (it replaces the file, or refuses a
  symlink) are copied once with `seed`, never stowed.
- **Never edit `/usr/share/omarchy/`**; it's owned by the omarchy package.

## Hyprland (Lua)

`modules/40-hyprland.sh` links `~/.config/supplement` -> `config/hypr` and
appends a `dofile` of `init.lua` to `~/.config/hypr/hyprland.lua`, so these
overrides load last. The `hl` and `o` globals are in scope; references are
`/usr/share/hypr/stubs/hl.meta.lua` and `/usr/share/omarchy/default/hypr/helpers.lua`.
Traps, all silent:

- `hl.bind`/`o.bind` *add* a bind; reusing a key needs `hl.unbind` first.
- `hyprctl keyword` and `hyprctl dispatch <legacy-name>` don't work: `hyprctl
  dispatch` evaluates Lua (`hyprctl dispatch 'hl.dsp.exec_cmd("…")'`), and
  plugins are only reachable as `hl.plugin.<ns>.*`.
- `require()` caches and Hyprland only clears its own prefixes on reload, so
  `init.lua` clears `supplement.*` itself and is reached with `dofile`.
- Display scale must NOT be set with `hl.monitor`: Omarchy's monitor-watch
  daemon re-applies it every 2s from `~/.config/hypr/monitors.lua`, which the
  module generates from `config/hypr/hosts/<hostname>.lua`.

## Shibumi

Installed from the source checkout at `~/.local/share/Shibumi-Shell` (latest
release tag, never `main`) via its `scripts/shibumi-suite`. Don't patch the
staged plugin files: since v0.2.3 the suite checks them against the release and
refuses `status`/`update` on any change (v0.2.3 also ships the `reloadPlugins`
startup fix we used to patch in).
