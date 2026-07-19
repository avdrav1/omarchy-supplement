# omarchy-supplement

Shell scripts and configuration that supplement an [Omarchy](https://omarchy.org/)
Arch Linux + Hyprland environment. Each `install-*.sh` provisions one concern;
`install-all.sh` runs them in dependency order. See `WARP.md` for the full
architecture and per-script reference.

## Hyprland overrides: two config trees

Omarchy migrated Hyprland configuration from hyprlang (`.conf`) to **Lua**. Both
trees live here so a fleet can be mid-migration:

| Parser | Overrides | Per-host scale | Entry point |
|---|---|---|---|
| Lua (current) | `hypr/lua/*.lua` | `hypr/lua/hosts/<hostname>.lua` | `require("supplement.init")` in `~/.config/hypr/hyprland.lua` |
| hyprlang (legacy) | `hyprland-overrides.conf` | `hosts/<hostname>.conf` | `source = <repo>/hyprland-overrides.conf` in `~/.config/hypr/hyprland.conf` |

`install-hyprland-overrides.sh` detects which parser the machine uses — Lua when
`~/.config/hypr/hyprland.lua` exists, since Hyprland prefers it — and wires up
only that tree. Either way the overrides load **last**, so they beat the
omarchy-managed `monitors.lua` / `monitors.conf`.

For the Lua tree the installer symlinks `~/.config/supplement` → `hypr/lua/`;
Hyprland's `package.path` already covers `~/.config/?.lua`, so no further path
setup is needed. The modules are:

- `init.lua` — entry point, requires the rest
- `monitors.lua` — resolves the per-host scale by hostname
- `input.lua` — keyboard, touchpad, cursor, DPMS
- `bindings.lua` — terminal/browser/web-app binds, vim-style focus, Snappy Switcher
- `scrolloverview.lua` — hyprpm plugin config, binds, and submap (no-ops when the
  plugin isn't built)

> **Changes must be made in both trees** until every machine has migrated.

## Per-machine display scaling

Display scale is HiDPI-dependent and therefore differs from machine to machine,
so it is **not** hardcoded in the shared Hyprland config. Instead each host has
its own tracked scale file, selected automatically by hostname.

### How it works

**Lua.** Each `hypr/lua/hosts/<hostname>.lua` returns a table:

```lua
return {
  scale = 1.5,
  gdk_scale = 1,
}
```

`install-hyprland-overrides.sh` reads that file and **generates**
`~/.config/hypr/monitors.lua` from it. Unlike everything else in the Lua tree,
the scale is applied by rendering a file rather than by an `hl.monitor` call in
the supplement — because Omarchy's `omarchy-hyprland-monitor-watch` daemon polls
every 2 seconds and force-reapplies the internal display's scale, reading it out
of `~/.config/hypr/monitors.lua` with:

```bash
sed -n 's/^local omarchy_monitor_scale = //p' ~/.config/hypr/monitors.lua
```

If that isn't a bare number the daemon falls back to a **hardcoded 2**, which is
exactly what the stock `= "auto"` value triggers. So an `hl.monitor` rule set
from anywhere else is silently reverted within seconds. The generated file keeps
that line in the shape the daemon expects; the original is saved once as
`monitors.lua.omarchy-orig`.

Because of this, changing the scale needs a re-run of the installer, not just a
`hyprctl reload`.

**hyprlang (legacy).** `hyprland-overrides.conf` sources
`~/.config/hypr/monitors.local.conf`, a **symlink** to a tracked
`hosts/<hostname>.conf` that defines `$MONSCALE` plus the monitor and GDK lines:

```ini
$MONSCALE = 1.5
env = GDK_SCALE,1
monitor = ,preferred,auto,$MONSCALE
```

The installer picks `hosts/$(hostname).conf`, seeding it from
`hosts/default.conf` if absent, then symlinks `monitors.local.conf` to it.

`GDK_SCALE` stays at `1` in both trees so Wayland fractional scaling drives GTK
apps rather than GDK doing its own integer upscaling on top; the monitor scale
value handles the actual scaling.

### Files

- `hypr/lua/hosts/<hostname>.lua` — tracked scale for a specific machine (e.g.
  `dellxps13.lua` uses `1.5`).
- `hypr/lua/hosts/default.lua` — fallback, used for any host without its own file.
- `hosts/<hostname>.conf`, `hosts/default.conf` — the legacy equivalents.
- `~/.config/supplement` — symlink to `hypr/lua/` (created by the installer).
- `~/.config/hypr/monitors.local.conf` — legacy per-machine symlink (created by
  the installer; not part of this repo).

### Common tasks

**Change the scale on the current machine**

1. Edit this machine's host file — `hypr/lua/hosts/<hostname>.lua` (and
   `hosts/<hostname>.conf` if other machines still run the legacy tree) — and set
   the scale (e.g. `2` for larger UI, `1` for native).
2. Apply it:
   ```bash
   ./install-hyprland-overrides.sh             # regenerates ~/.config/hypr/monitors.lua
   hyprctl reload
   hyprctl configerrors                        # must be empty
   sleep 5; hyprctl monitors | grep -E 'Monitor|scale:'
   ```
   Wait a few seconds before checking: the clamshell daemon reapplies the scale
   on a 2-second poll, so an immediate read can catch the old value.
3. Commit the change so it persists across rebuilds:
   ```bash
   git add hypr/lua/hosts/<hostname>.lua && git commit -m "Set <hostname> scale"
   ```

Common values: HiDPI laptop panels (e.g. 3840x2400 13") → `1.5` or `2`;
1080p / 1440p / ultrawide → `1`.

**Provision a new machine**

1. Run `./install-all.sh` (or just `./install-hyprland-overrides.sh`). It seeds
   the machine's host file from the default and wires up the right tree.
2. Set the scale in the new host file, run `hyprctl reload`, and commit the file
   so the machine is tracked.

**Add a machine's config ahead of time**

Create `hypr/lua/hosts/<hostname>.lua` (copy `default.lua`), set the scale, and
commit. When that machine next runs the installer it will use the existing file
instead of seeding a new one.

### Verifying without SSH

Because every machine's intended scale lives in its tracked host file, you can
inspect or correct any host's scaling from any checkout of this repo — no need to
log into the machine. The value takes effect there once the installer runs and
`hyprctl reload` is issued.
