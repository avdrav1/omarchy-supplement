-- Hyprland config for apps and shell plugins installed by install-apps.sh and
-- install-shell-plugins.sh. Every block is guarded on the app or plugin being
-- present, so a machine that skipped one gets nothing from it rather than a
-- bind that launches nothing.
--
-- These used to live in the reference machine's own ~/.config/hypr files,
-- which is why no other machine had them.

local plugins = os.getenv("HOME") .. "/.config/omarchy/plugins/"

local function plugin_present(id)
  local handle = io.open(plugins .. id .. "/manifest.json", "r")
  if handle then
    handle:close()
    return true
  end
  return false
end

-- Vesktop (Discord). SUPER+D is bound in bindings.lua. Starts in the tray at
-- login; pings don't pull focus; the same subtle transparency as the
-- terminals; the call popout floats like other PiP.
if o.cmd_present("vesktop") then
  o.launch_on_start("vesktop --start-minimized")
  o.window("^vesktop$", { focus_on_activate = false })
  o.transparent_window("^vesktop$")
  o.window({ class = "^vesktop$", title = "^Discord Popout$" }, { tag = "+pip" })
end

-- Spotlight launcher (mihai.spotlight). The backslash is bound by keycode (51)
-- so it works on any layout; ALT+\ covers keyboards whose right-hand modifier
-- sends Right Alt rather than SUPER (the Keychron).
if plugin_present("mihai.spotlight") then
  local spotlight = "omarchy-shell shell summon mihai.spotlight '{}'"
  o.bind("ALT + SPACE", "Spotlight launcher", spotlight)
  o.bind("SUPER + code:51", "Spotlight launcher", spotlight)
  o.bind("ALT + code:51", "Spotlight launcher", spotlight)
end

-- Altscape (ALT+TAB preview switcher). Its ALT+TAB binds are NOT here: the
-- plugin's own `altscape-binds sync` writes them in a marked block at the end
-- of ~/.config/hypr/hyprland.lua, after this tree, and rewrites that block when
-- the key is changed in its settings. This adds the settings window: SUPER+ALT+A
-- opens it (Shibumi has no bar slot for the plugin's button), floating and
-- centered.
if plugin_present("io.github.qempexe.altscape") then
  o.window({ class = "org.quickshell", title = "^Altscape$" }, { float = true })
  o.window({ class = "org.quickshell", title = "^Altscape$" }, { center = true })
  o.window({ class = "org.quickshell", title = "^Altscape$" }, { size = { 1000, 780 } })
  o.bind("SUPER + ALT + A", "Altscape settings", "omarchy-shell io.github.qempexe.altscape settings")
end
