-- hyprland-scroll-overview (hyprpm plugin "scrolloverview", by yayuuu).
-- Workspace overview driven by touchpad scroll.
-- Upstream: https://github.com/yayuuu/hyprland-scroll-overview
-- Installed by install-hyprland-scroll-overview.sh.
--
-- The plugin is built by hyprpm against the *currently installed* Hyprland, so
-- after every Hyprland upgrade it must be rebuilt with `hyprpm update` or it
-- silently stops loading. hypr/hyprpm-plugins.hook prints a reminder after any
-- Hyprland upgrade.
--
-- Lua-parser notes:
--
-- * The plugin dual-registers: hyprlang dispatchers (scrolloverview:overview,
--   ...) AND a Lua namespace via HyprlandAPI::addLuaFunction. Only the Lua
--   namespace is reachable from a Lua config -- `hyprctl dispatch <name>` now
--   evaluates Lua, and hl.dsp has no call-dispatcher-by-name escape hatch, so
--   the legacy dispatcher names are dead here. Use hl.plugin.scrolloverview.*.
--
-- * hl.plugin.scrolloverview.overview("toggle") is dual-mode: called at config
--   level it RETURNS a dispatcher for hl.bind, but called inside a
--   `function() ... end` bind callback it EXECUTES immediately. Both forms are
--   used below -- the plain binds take the returned dispatcher, and the
--   multi-step select relies on immediate execution.
--
-- * Plugin config keys and the Lua namespace only exist once the plugin has
--   loaded, so everything here is behind the load guard. Unlike the legacy
--   config, an absent plugin is silent rather than a wall of "Invalid
--   dispatcher" in `hyprctl configerrors`.
--
-- * Do NOT call hl.plugin.load(path) from here. On 0.55.4 it does not merely
--   fail -- calling it during config evaluation DEADLOCKS the compositor before
--   it finishes init, so no Wayland socket is ever created, uwsm's
--   wayland-session-waitenv times out after 30s and SDDM reclaims the session:
--   a blank screen after login, with only a TTY to recover from. The symptom is
--   the main thread parked in do_wait rather than do_epoll_wait. It only bites
--   once hyprpm has actually built the .so, which is why logins keep working
--   until install-hyprland-scroll-overview.sh is run.
--
-- * The only working load path is `hyprpm reload`, hence the start hook below
--   (the hyprlang tree does the same with `exec-once = hyprpm reload -n`). It
--   needs no sudo -- the .so in the root-owned cache is world-readable.

local plugin = hl.plugin.scrolloverview

if not plugin then
  -- Startup: plugins load *after* the config is evaluated, so the namespace is
  -- absent on this pass and every bind below would be skipped. Load the plugins
  -- and re-evaluate -- on the second pass `plugin` is non-nil and the rest of
  -- this file registers normally.
  --
  -- hl.on("hyprland.start") fires once per session, not on `hyprctl reload`, so
  -- the nested reload cannot recurse. A manual reload while the plugin is
  -- genuinely missing (not built, or not rebuilt since the last Hyprland
  -- upgrade -- run ./install-hyprland-scroll-overview.sh) just returns silently.
  o.exec_on_start("hyprpm reload -n && hyprctl reload")
  return
end

hl.config({
  plugin = {
    scrolloverview = {
      layout = "vertical", -- workspaces stack top-to-bottom
      scale = 0.5, -- size of each workspace thumbnail
      workspace_gap = 20, -- separation between thumbnails (default 0)
      blur = false, -- true for a blurred backdrop (costs GPU)

      input = {
        -- The touchpad already has scroll_factor = 0.4 from input.lua. This
        -- multiplies on top of that, so raise it if the overview feels
        -- sluggish to scroll.
        touchpad_scroll_factor = 1.0,
        scroll_event_delay = 200,
      },
    },
  },
})

-- SUPER+G is the plugin's documented example bind, but it's taken here (Notion,
-- see bindings.lua), so the overview lives on SUPER+` instead.
--
-- SUPER+grave is ALSO fcitx5's default "Quick Phrase" trigger, and fcitx5 grabs
-- it at the input-method layer, so Hyprland never sees the conflict -- the
-- overview opens and a Quick Phrase prompt pops up on the same press. It is
-- unbound in the dotfiles repo (fcitx5/.config/fcitx5/conf/quickphrase.conf,
-- installed by install-dotfiles.sh); if the prompt reappears, that stow symlink
-- was likely clobbered by fcitx5-configtool.
o.bind("SUPER + grave", "Workspace overview", plugin.overview("toggle"))

-- The plugin has built-in keyboard nav, but it wasn't picking up arrow keys
-- here. Defining this submap replaces that built-in handling with explicit
-- binds; the plugin enters the submap automatically while the overview is open.
--
-- While the overview is open, normal binds are inactive unless they carry
-- submap_universal (see the ALT+1..9 binds below).
hl.define_submap("scrolloverview", function()
  hl.bind("left", plugin.navigate("left"))
  hl.bind("right", plugin.navigate("right"))
  hl.bind("up", plugin.navigate("up"))
  hl.bind("down", plugin.navigate("down"))

  -- Selecting is a three-step sequence: pick the workspace, pick the window
  -- under the selection, then close the overview. `overview("select")` alone
  -- only does the first step -- it switches workspace but never focuses the
  -- window. Inside this callback the plugin calls run immediately, so they
  -- chain in order.
  local function select()
    plugin.overview("select")
    plugin.window("select")
    plugin.overview("off")
  end

  hl.bind("return", select)
  hl.bind("mouse:272", select, { mouse = true })

  hl.bind("escape", plugin.overview("off"))
  hl.bind("mouse:274", plugin.window("close"), { mouse = true })
end)

-- Jump straight to a workspace from inside the overview. These are global binds
-- carrying submap_universal, which is what keeps them alive while the
-- scrolloverview submap has the keyboard.
--
-- ALT+1..9 was entirely free -- the only ALT binds are media keys, PRINT and TAB.
-- code:10..18 = number row 1..9, matching Omarchy's layout-independent convention.
for workspace = 1, 9 do
  o.bind(
    "ALT + code:" .. tostring(workspace + 9),
    "Switch to workspace " .. workspace .. " (overview)",
    hl.dsp.focus({ workspace = tostring(workspace) }),
    { submap_universal = true }
  )
end
