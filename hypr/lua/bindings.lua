-- Personal keybinding overrides.
--
-- Omarchy's defaults are already loaded, so anything reused below must be
-- unbound first -- hl.bind does not replace an existing bind, it adds another
-- one on the same key.
--
-- See the current set with: omarchy menu keybindings --print

local terminal = "uwsm app -- ghostty"

-- Scaled down because Chromium's own default UI scale runs large here.
-- NOTE: this was tuned when the display was at scale 2. Revisit if the value
-- looks wrong now that hosts/<hostname>.lua drives the monitor scale.
local browser = "chromium --force-device-scale-factor=0.8"

-- Default editor for Hyprland-spawned children (e.g. the omarchy menu's
-- "Edit monitors" action). omarchy-launch-editor reads $EDITOR, and the omarchy
-- menu is bound as a direct exec, so it inherits Hyprland's env rather than the
-- shell's. ~/.zshrc keeps nvim as the terminal $EDITOR; this only affects the
-- graphical session. env vars apply at login, not on reload.
hl.env("EDITOR", "fresh")
hl.env("SUDO_EDITOR", "fresh")

-- Only ever use Ghostty, never Omarchy's configured terminal.
hl.unbind("SUPER + RETURN")
o.bind("SUPER + RETURN", "Terminal", terminal)

hl.unbind("SUPER + B")
o.bind("SUPER + B", "Browser", browser)

-- Web apps. SUPER+G is Omarchy's "Toggle window grouping" by default.
hl.unbind("SUPER + D")
o.bind("SUPER + D", "Discord", { webapp = "https://discord.com/channels/@me" })

hl.unbind("SUPER + G")
o.bind("SUPER + G", "Notion", { webapp = "https://www.notion.so/" })

-- Vim-style focus movement. This takes over three Omarchy defaults:
--   SUPER+J  Toggle window split
--   SUPER+K  Show key bindings (remapped to SUPER+SHIFT+K below)
--   SUPER+L  Toggle workspace layout
hl.unbind("SUPER + H")
hl.unbind("SUPER + J")
hl.unbind("SUPER + K")
hl.unbind("SUPER + L")

o.bind("SUPER + H", "Focus on left window", hl.dsp.focus({ direction = "l" }))
o.bind("SUPER + L", "Focus on right window", hl.dsp.focus({ direction = "r" }))
o.bind("SUPER + K", "Focus on above window", hl.dsp.focus({ direction = "u" }))
o.bind("SUPER + J", "Focus on below window", hl.dsp.focus({ direction = "d" }))

-- SUPER+K now focuses the window above, so relocate the Omarchy keybindings
-- cheat sheet (default SUPER+K) to SUPER+SHIFT+K.
o.bind("SUPER + SHIFT + K", "Show key bindings", "omarchy-menu-keybindings")

-- TAB is deliberately left alone here. This block used to hand ALT+TAB and
-- SUPER+TAB to Snappy Switcher; that package is no longer installed by this
-- repo. QuickSwitch (supplement.quickswitch, required last from init.lua) takes
-- SUPER+TAB for its preview switcher, and ALT+TAB falls back to Omarchy's stock
-- "focus next window / bring to top" from default/hypr/bindings/tiling.lua.

-- Strata file manager (Miller-column, keyboard-first). Installed via
-- install-strata.sh, which also writes the .desktop entry and makes Strata the
-- XDG handler for the file-manager MIME types (folders, mounts, file:// and
-- trash://). Archive types stay with Nautilus: Strata extracts only from its
-- right-click menu and would otherwise just reveal a .zip in its parent folder.
--
-- Replaces Omarchy's two Nautilus binds. Both are unbound first -- o.bind adds
-- rather than replaces, so skipping the unbind launches Nautilus *and* Strata
-- on one press.
--
-- Bound here in the Lua tree only. The legacy hyprland-overrides.conf keeps
-- SUPER+SHIFT+F for re-enabling the internal display (paired with SUPER+SHIFT+D
-- to disable it), so Strata deliberately has no hyprlang counterpart -- see the
-- note beside that bind.
hl.unbind("SUPER + SHIFT + F")
hl.unbind("SUPER + ALT + SHIFT + F")

o.bind("SUPER + SHIFT + F", "File manager", "uwsm app -- strata")
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)",
  "uwsm app -- strata \"$(omarchy-cmd-terminal-cwd)\"")

-- BlueFerry -- an iPhone's SMS/RCS/iMessage over Bluetooth. Installed by
-- install-blueferry.sh, which also places its widget on the bar.
--
-- No unbind needed: SUPER+M is free in stock Omarchy. SUPER+SHIFT+M is Music
-- and SUPER+ALT+SHIFT+M the music TUI, so this sits in the same mnemonic
-- family without colliding with either.
--
-- Deliberately the GTK client, not blueferry-quickshell: it is a Gio
-- single-instance application, so a second press raises the window it already
-- opened rather than starting a second client, and it is an ordinary toplevel
-- Hyprland can tile. The Quickshell client is what the bar widget drives.
-- Silently does nothing when BLUEFERRY_CLIENTS left the GTK package out.
o.bind("SUPER + M", "Messages (BlueFerry)", "uwsm app -- blueferry-gtk")

-- Cycle audio outputs with SUPER+mute as well as Omarchy's stock SHIFT+mute
-- (default/hypr/bindings/media.lua) -- same command, a key that is easier to
-- hit one-handed. locked = true so it also works on the lock screen. SUPER+mute
-- is unbound in stock Omarchy, so no unbind is needed.
o.bind("SUPER + XF86AudioMute", "Switch audio output", "omarchy-audio-output-switch", { locked = true })
