-- Monitor + scale for av-framework. See hosts/default.lua for the scale guide.
-- Framework 13 AMD: 13.5" 2880x1920 eDP-1. 1.5 divides evenly (-> 1920x1280
-- effective); Omarchy's stock scale 2 (1440x960) is too zoomed in on this panel.
return {
  scale = 1.5,
  gdk_scale = 1,
}
