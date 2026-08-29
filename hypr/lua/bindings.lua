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

-- Snappy Switcher (fast Alt+Tab window switcher). Installed via
-- install-snappy-switcher.sh; user config.ini comes from the dotfiles repo.
-- Replaces Omarchy's ALT+TAB (cycle windows) and SUPER+TAB (next workspace).
-- The daemon is a single-instance server: it binds
-- $XDG_RUNTIME_DIR/snappy-switcher.sock, and a second instance *unlinks and
-- takes over* that socket, killing the first. So never start it raw when the
-- packaged systemd user unit may already have. Delegate to the unit (a no-op
-- when it is already running) and fall back to a direct start only on machines
-- whose snappy-switcher package predates the unit.
-- install-snappy-switcher.sh repairs the unit's sandbox and enables it.
o.exec_on_start("systemctl --user start snappy-switcher.service || snappy-switcher --daemon")

hl.unbind("ALT + TAB")
hl.unbind("SUPER + TAB")

o.bind("ALT + TAB", "Snappy Switcher Next", "snappy-switcher next --mod alt")
o.bind("SUPER + TAB", "Snappy Switcher Workspace Next", "snappy-switcher next --workspace --mod super")
