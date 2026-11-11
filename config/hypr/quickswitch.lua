-- QuickSwitch -- macOS-style task switcher with window previews.
--   Plugin: https://github.com/ewweberlin/QuickSwitch
--   Installed by install-quickswitch.sh (omarchy plugin add --enable).
--
-- The plugin ships its own bindings file and asks you to dofile it from
-- ~/.config/hypr/bindings.lua. Load it LAST instead, from init.lua: hyprland.lua
-- requires hypr.bindings BEFORE this supplement tree, and last bind wins, so
-- anything that rebinds SUPER+TAB after this file silently overrides it -- no
-- error, and `hyprctl configerrors` stays clean, so it just looks like the
-- switcher is broken. (That is exactly what happened while supplement/bindings.lua
-- still bound SUPER+TAB to Snappy Switcher.)
--
-- Required last, the plugin's own hl.unbind("SUPER + TAB") takes the key off
-- Omarchy's "next workspace" default. ALT+TAB is deliberately left alone and
-- keeps Omarchy's stock cycle-next behavior.
--
-- The plugin also rebinds SUPER+arrows to its own GlobalShortcuts, because
-- Omarchy's directional-focus binds would otherwise consume those keys before
-- they reach the overlay's exclusive keyboard grab. Its handler re-dispatches
-- the normal focus command whenever the switcher is closed, so directional
-- focus is unchanged. SUPER+H/J/K/L (bound in supplement/bindings.lua) are not
-- touched by any of this.
--
-- Guarded on existence, not on hostname: this repo is shared by machines that
-- have never run install-quickswitch.sh, and dofile() on a missing path is a
-- hard Lua error that would take the whole supplement tree down with it --
-- including the binds and monitor setup below it. Absent plugin = silent no-op.

local bindings = os.getenv("HOME")
  .. "/.config/omarchy/plugins/ewweberlin.quickswitch/task-switch-bindings.lua"

local handle = io.open(bindings, "r")
if handle then
  handle:close()
  dofile(bindings)
end
