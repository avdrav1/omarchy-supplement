.pragma library

// Pure helpers for the switcher, kept out of QML so they stay easy to reason
// about. Input is the JSON array from `hyprctl clients -j`.

var MINIMIZED_WORKSPACE = "special:minimized"
var MAX_TITLE = 300

function clip(value, max) {
  var s = String(value === undefined || value === null ? "" : value)
  return s.length > max ? s.substring(0, max) : s
}

// Windows in most-recently-used order (focusHistoryID 0 = focused now).
// Unmapped/hidden windows and anything without a real address are dropped.
function buildWindows(raw) {
  var list
  try { list = JSON.parse(raw) } catch (e) { return [] }
  if (!Array.isArray(list)) return []

  var out = []
  for (var i = 0; i < list.length && out.length < 200; i++) {
    var c = list[i]
    if (!c || c.mapped === false || c.hidden === true) continue
    var address = String(c.address || "")
    if (!/^0x[0-9a-f]+$/i.test(address)) continue
    var ws = c.workspace || {}
    var wsName = clip(ws.name, 64)
    var history = Number(c.focusHistoryID)
    out.push({
      address: address,
      appClass: clip(c["class"] || c.initialClass, 128),
      title: clip(c.title || c.initialTitle, MAX_TITLE),
      workspaceId: Number(ws.id) || 0,
      workspaceName: wsName,
      minimized: wsName === MINIMIZED_WORKSPACE,
      special: wsName.indexOf("special:") === 0,
      history: isFinite(history) && history >= 0 ? history : 9999
    })
  }
  out.sort(function(a, b) { return a.history - b.history })
  return out
}

// Selection to start on: the previously used window, so a single tap of
// Alt+Tab flips back. `step` is +1 for next, -1 for prev.
function initialIndex(count, step) {
  if (count <= 1) return 0
  return step < 0 ? count - 1 : 1
}

function wrap(index, count) {
  if (count <= 0) return 0
  return ((index % count) + count) % count
}

function windowSpec(address) {
  return "window = \"address:" + address + "\""
}

// Lua dispatches (Hyprland's Lua config) to bring a window forward.
function focusSteps(win, currentWorkspaceId) {
  var target = windowSpec(win.address)
  var steps = []
  if (win.minimized && currentWorkspaceId >= 1)
    steps.push("hl.dsp.window.move({ workspace = \"" + currentWorkspaceId + "\", " + target + " })")
  steps.push("hl.dsp.focus({ " + target + " })")
  steps.push("hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })")
  return steps
}

function closeStep(win) {
  return "hl.dsp.window.close({ " + windowSpec(win.address) + " })"
}
