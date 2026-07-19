-- Entry point for the omarchy-supplement Hyprland overrides (Lua parser).
--
-- Omarchy migrated Hyprland config from hyprlang (.conf) to Lua. The legacy
-- tree in this repo -- hyprland-overrides.conf plus hosts/<hostname>.conf --
-- is kept for machines still on the old parser; the modules here are the Lua
-- equivalent. install-hyprland-overrides.sh picks whichever the machine needs.
--
-- Wiring: install-hyprland-overrides.sh symlinks ~/.config/supplement to this
-- directory and appends `require("supplement.init")` to ~/.config/hypr/hyprland.lua.
-- Hyprland's package.path already covers ~/.config/?.lua, so no path setup is
-- needed here. This is required LAST, after Omarchy's defaults, so everything
-- below overrides them.
--
-- The `hl` (Hyprland API) and `o` (Omarchy helpers) globals are both already in
-- scope by the time this loads. API reference: /usr/share/hypr/stubs/hl.meta.lua
--
-- RELOAD: Omarchy's bootstrap.lua clears package.loaded only for its own module
-- prefixes ("default.hypr", "hypr", "omarchy.current.theme"). "supplement" is
-- not among them, so without the loop below our modules would be cached after
-- first load and silently never re-run on `hyprctl reload` -- edits would
-- appear to do nothing, and the last-wins ordering against Omarchy's defaults
-- would differ between the initial load and every reload after it.
--
-- This file is itself reached by dofile (not require) from hyprland.lua for the
-- same reason: dofile always re-executes.
for module in pairs(package.loaded) do
  if module:sub(1, #"supplement.") == "supplement." then
    package.loaded[module] = nil
  end
end

-- NOTE: monitor scale is deliberately NOT set here. Omarchy's
-- omarchy-hyprland-monitor-watch daemon polls every 2s and force-reapplies the
-- internal display's scale, parsing it out of ~/.config/hypr/monitors.lua with
-- sed -- so any hl.monitor rule set from this tree is overwritten within
-- seconds. install-hyprland-overrides.sh instead renders that file from
-- hosts/<hostname>.lua. See hypr/lua/hosts/default.lua.

require("supplement.input")
require("supplement.bindings")
require("supplement.scrolloverview")
