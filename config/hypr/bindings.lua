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

-- Strata replaces Folio (modules/45-strata.sh); stock omarchy-launch-files
-- hardcodes folio, so both file-manager binds are taken over here.
local strata = os.getenv("HOME") .. "/.local/bin/strata"
hl.unbind("SUPER + SHIFT + F")
hl.unbind("SUPER + ALT + SHIFT + F")
o.bind("SUPER + SHIFT + F", "File manager", { launch = strata })
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)",
  "uwsm-app -- " .. strata .. " \"$(omarchy-cmd-terminal-cwd)\"")

-- Web apps. SUPER+G is Omarchy's "Toggle window grouping" by default.
-- Discord is Vesktop where it is installed (focuses the running window, or
-- raises it from the tray), and the web app everywhere else.
hl.unbind("SUPER + D")
if o.cmd_present("vesktop") then
  o.bind("SUPER + D", "Discord", o.launch_sole("^vesktop$", "vesktop"))
else
  o.bind("SUPER + D", "Discord", { webapp = "https://discord.com/channels/@me" })
end

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
-- Cycle audio outputs with SUPER+mute as well as Omarchy's stock SHIFT+mute
-- (default/hypr/bindings/media.lua) -- same command, a key that is easier to
-- hit one-handed. locked = true so it also works on the lock screen. SUPER+mute
-- is unbound in stock Omarchy, so no unbind is needed.
o.bind("SUPER + XF86AudioMute", "Switch audio output", "omarchy-audio-output-switch", { locked = true })

-- Alt+Tab: the Shibumi switcher (config/shell-plugins/av.shibumi-switcher,
-- installed by modules/70-shibumi.sh). Tab/Shift+Tab move through windows in
-- most-recently-used order; letting go of Alt focuses the selection. Falls back
-- to Omarchy's stock cycle_next until the plugin is installed.
local switcher_manifest = os.getenv("HOME") .. "/.config/omarchy/plugins/av.shibumi-switcher/manifest.json"
local switcher_file = io.open(switcher_manifest, "r")
if switcher_file then
  switcher_file:close()
  local switcher = "omarchy-shell -q shibumi-switcher "
  hl.unbind("ALT + TAB")
  hl.unbind("ALT + SHIFT + TAB")
  o.bind("ALT + TAB", "Switch windows", switcher .. "next")
  o.bind("ALT + SHIFT + TAB", "Switch windows (back)", switcher .. "prev")
  o.bind("ALT + ALT_L", nil, switcher .. "release", { release = true })
  o.bind("ALT + ALT_R", nil, switcher .. "release", { release = true })
end

-- Spotlight launcher (mihai.spotlight, installed by modules/70-shibumi.sh).
-- The backslash is bound by keycode (51) so it works on any layout; ALT+\
-- covers keyboards whose right-hand modifier sends Right Alt rather than SUPER
-- (the Keychron). ALT+SPACE is Omarchy's dictation toggle when a dictation
-- backend is installed, so it is unbound first.
local spotlight_file = io.open(os.getenv("HOME") .. "/.config/omarchy/plugins/mihai.spotlight/manifest.json", "r")
if spotlight_file then
  spotlight_file:close()
  local spotlight = "omarchy-shell shell summon mihai.spotlight '{}'"
  hl.unbind("ALT + SPACE")
  o.bind("ALT + SPACE", "Spotlight launcher", spotlight)
  o.bind("SUPER + code:51", "Spotlight launcher", spotlight)
  o.bind("ALT + code:51", "Spotlight launcher", spotlight)
end
