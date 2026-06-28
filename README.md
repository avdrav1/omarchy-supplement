# omarchy-supplement

Shell scripts and configuration that supplement an [Omarchy](https://omarchy.org/)
Arch Linux + Hyprland environment. Each `install-*.sh` provisions one concern;
`install-all.sh` runs them in dependency order. See `WARP.md` for the full
architecture and per-script reference.

## Per-machine display scaling

Display scale is HiDPI-dependent and therefore differs from machine to machine,
so it is **not** hardcoded in the shared Hyprland config. Instead each host has
its own tracked scale file, selected automatically by hostname.

### How it works

- `hyprland-overrides.conf` is sourced last in `~/.config/hypr/hyprland.conf`
  (wired up by `install-hyprland-overrides.sh`), so it overrides the
  omarchy-managed `~/.config/hypr/monitors.conf`. It does not set a scale
  directly; it sources a per-machine file:
  ```ini
  source = ~/.config/hypr/monitors.local.conf
  ```
- `~/.config/hypr/monitors.local.conf` is a **symlink** to a tracked per-host
  file under `hosts/`:
  ```
  ~/.config/hypr/monitors.local.conf -> hosts/<hostname>.conf
  ```
- Each `hosts/<hostname>.conf` defines a `$MONSCALE` variable plus the monitor
  and GDK scale lines. `hyprland-overrides.conf` reuses `$MONSCALE` in its
  lid-switch and `SUPER SHIFT F` rules, so the scale is defined in exactly one
  place per machine:
  ```ini
  $MONSCALE = 1.5
  env = GDK_SCALE,1
  monitor = ,preferred,auto,$MONSCALE
  ```
- `install-hyprland-overrides.sh` performs the selection: it picks
  `hosts/$(hostname).conf`, seeding it from `hosts/default.conf` if it does not
  exist yet, then symlinks `monitors.local.conf` to it.

`GDK_SCALE` stays at `1` so Wayland fractional scaling drives GTK apps; the
`$MONSCALE` value handles the actual scaling.

### Files

- `hosts/<hostname>.conf` — tracked scale for a specific machine (e.g.
  `hosts/dellxps13.conf` uses `1.5`).
- `hosts/default.conf` — fallback template (`$MONSCALE = 1`) used to seed a new
  machine's host file.
- `~/.config/hypr/monitors.local.conf` — per-machine symlink (created by the
  installer; not part of this repo).

### Common tasks

**Change the scale on the current machine**

1. Edit this machine's host file, e.g. `hosts/dellxps13.conf`, and set
   `$MONSCALE` (e.g. `2` for larger UI, `1` for native).
2. Apply it:
   ```bash
   hyprctl reload
   hyprctl monitors | grep -A1 <your-output>   # confirm the new scale
   ```
3. Commit the change so it persists across rebuilds:
   ```bash
   git add hosts/<hostname>.conf && git commit -m "Set <hostname> scale"
   ```

Common `$MONSCALE` values: HiDPI laptop panels (e.g. 3840x2400 13") → `1.5` or
`2`; 1080p / 1440p / ultrawide → `1`.

**Provision a new machine**

1. Run `./install-all.sh` (or just `./install-hyprland-overrides.sh`). It
   creates `hosts/<hostname>.conf` from `hosts/default.conf` and symlinks
   `~/.config/hypr/monitors.local.conf` to it.
2. Set `$MONSCALE` in the new `hosts/<hostname>.conf`, run `hyprctl reload`, and
   commit the file so the machine is tracked.

**Add a machine's config ahead of time**

Create `hosts/<hostname>.conf` (copy `hosts/default.conf`), set `$MONSCALE`, and
commit. When that machine next runs the installer it will symlink to the
existing file instead of seeding a new one.

### Verifying without SSH

Because every machine's intended scale lives in `hosts/<hostname>.conf`, you can
inspect or correct any host's scaling from any checkout of this repo — no need
to log into the machine. The value takes effect there once the installer runs
(or you recreate the symlink manually) and `hyprctl reload` is issued.
