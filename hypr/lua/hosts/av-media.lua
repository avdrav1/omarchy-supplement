-- Fallback per-machine monitor + scale, used when hosts/<hostname>.lua does
-- not exist yet. On a new machine, copy this to hosts/<hostname>.lua, set the
-- scale, and commit it so the machine is tracked in git.
--   HiDPI laptop panel (e.g. 3840x2400 13") -> 1.5 or 2
--   1080p / 1440p / ultrawide               -> 1
return {
  scale = 1,
  gdk_scale = 1,
}
