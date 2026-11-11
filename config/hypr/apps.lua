-- Hyprland config for apps installed by modules/10-packages.sh. Every block is
-- guarded on the app being present, so a machine without it gets nothing from
-- it rather than a bind that launches nothing.
--
-- These used to live in the reference machine's own ~/.config/hypr files,
-- which is why no other machine had them.

-- Vesktop (Discord). SUPER+D is bound in bindings.lua. Starts in the tray at
-- login; pings don't pull focus; the same subtle transparency as the
-- terminals; the call popout floats like other PiP.
if o.cmd_present("vesktop") then
  o.launch_on_start("vesktop --start-minimized")
  o.window("^vesktop$", { focus_on_activate = false })
  o.transparent_window("^vesktop$")
  o.window({ class = "^vesktop$", title = "^Discord Popout$" }, { tag = "+pip" })
end
