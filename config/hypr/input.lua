-- Input, cursor, and DPMS overrides.
--
-- hl.config merges into Omarchy's defaults, so only the keys set here change;
-- everything else (kb_layout from /etc/vconsole.conf, follow_mouse,
-- clickfinger_behavior, ...) keeps the Omarchy value.

hl.config({
  input = {
    -- Caps Lock acts as Ctrl. This replaces Omarchy's default
    -- kb_options = "compose:caps".
    kb_options = "ctrl:nocaps",

    -- Faster than the Omarchy default (40 / 250).
    repeat_rate = 50,
    repeat_delay = 220,

    touchpad = {
      scroll_factor = 0.4,
    },
  },

  misc = {
    mouse_move_enables_dpms = true,
    key_press_enables_dpms = true,
  },

  cursor = {
    -- Don't teleport the pointer onto a window when it's focused/activated.
    -- Omarchy sets misc:focus_on_activate, so newly-opened windows (e.g. an
    -- aerc terminal) grab focus and, with warping on, the cursor jumps to
    -- them. This keeps the pointer where it is; focus-follows-mouse still works.
    no_warps = true,
  },
})
