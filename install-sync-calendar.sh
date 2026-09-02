#!/bin/bash

set -euo pipefail

# Install promaaa's Calendar Sync clock -- a bar clock that syncs Google,
# iCloud, Proton, Outlook, Fastmail/JMAP, Nextcloud and generic .ics feeds into
# a calendar popup -- and wire it into whichever bar this machine actually runs.
#   Upstream: https://github.com/promaaa/sync-calendar-omarchy
#
# Upstream's post-install steps assume the *stock* Omarchy bar:
#
#     omarchy plugin disable omarchy.clock
#     omarchy bar move promaa.clock --section center
#     sed -i 's/"centerAnchor": "[^"]*"/"centerAnchor": "promaa.clock"/' shell.json
#
# On a Shibumi machine (install-shibumi.sh), which is what this fleet runs, all
# three are silent no-ops:
#
#   * The visible clock is NOT omarchy.clock. Shibumi draws it inside
#     hancore.shibumi.center -- group role "G8" -- a composite pill that also
#     carries the weather icon, the date, and the update dot. It has no
#     clock-only toggle, so hiding the clock means hiding the whole group, and
#     the weather/update widgets have to be re-added separately.
#   * `omarchy bar move` edits bar.layout, but Shibumi in v2 shell style
#     (bar.shibumi.presentation.shellStyle != "shibumi") lays the bar out from
#     bar.shibumi.v2Layout. bar.layout only decides which plugins get *loaded*.
#   * centerAnchor is dead on Shibumi. Its bar parses the key into a property
#     nothing consumes (core/CenterSection.qml is never instantiated), and
#     shibumi-manager rewrites it to hancore.shibumi.center on every activation.
#
# TWO TRAPS, and between them the reason hand-editing shell.json appears to do
# nothing at all:
#
#   1. Both layout validators (core/V2LayoutModel.js valid(),
#      core/LayoutModel.js validOrder()) require *every* fixed group -- G1..G18
#      in v2, G1..G15 in v1 -- to be present in the layout. Deleting "G8"
#      outright makes the whole layout invalid and the bar silently falls back
#      to Shibumi's built-in default, which puts the old clock straight back in
#      the center. G8 must stay in the array and be hidden with
#      widgets.G8.enabledV2 = false; we park it in the last right-hand slot.
#
#      Shibumi centers the center RUN as a whole -- there is no per-widget
#      anchor (that is what the dead centerAnchor would have been). So the
#      clock sits on the true midpoint only while whatever flanks it is
#      symmetric. We flank it with the weather pill on the left and the update
#      pill on the right, both single-glyph buttons of the same slot width, so
#      it stays centered. Note the update pill is `visible: updateAvailable`:
#      with no update pending it collapses and the run shifts right by half its
#      width. That is inherent to run-centering, not a misconfiguration.
#   2. omarchy.weather and omarchy.system-update cannot simply be put back on
#      the bar to replace what G8 was showing. Both are on Shibumi's
#      GroupRegistry.js ConsumedAliases list -- stock widgets it claims for its
#      own suite -- so isAssignedModule() rejects them as dynamic providers and
#      V2LayoutModel.reconcilePluginGroups() prunes them right back out as
#      stale on the next reload. `omarchy plugin clone` sidesteps this: the
#      clone gets a "<user>." id that is not on the blocklist, and Shibumi
#      accepts it as an ordinary third-party widget -- the same path that gets
#      promaa.clock onto the bar at all.
#
# Re-runnable: the plugin is updated rather than re-added, clones are made only
# when missing, and the shell.json rewrite is a no-op once the layout matches.

REPO_URL="https://github.com/promaaa/sync-calendar-omarchy.git"
PLUGIN_ID="promaa.clock"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

# Omarchy's bin dir is not guaranteed on PATH in a non-interactive run; without
# it every omarchy-* call below would silently do nothing.
for d in "$HOME/.local/share/omarchy/bin" /usr/share/omarchy/bin; do
  [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH

command -v omarchy >/dev/null 2>&1 || {
  echo "ERROR: the omarchy CLI is not on PATH; is this an Omarchy machine?" >&2
  exit 1
}

# ── Runtime dependencies ─────────────────────────────────────────────────────
# The widget's fetcher is a plain python3 script (stdlib only -- it speaks HTTP
# to .ics/JMAP endpoints itself), and the agenda copy button shells out to
# wl-copy. Install only what's missing so a re-run on a provisioned machine
# never reaches for sudo.
deps=(python wl-clipboard)
missing=()
for pkg in "${deps[@]}"; do
  pacman -Qq "$pkg" &>/dev/null || missing+=("$pkg")
done
if ((${#missing[@]})); then
  sudo pacman -S --noconfirm --needed "${missing[@]}"
fi

# ── Install or update the plugin ─────────────────────────────────────────────
# `omarchy plugin add` clones into ~/.config/omarchy/plugins/<manifest id> and,
# with --enable, drops the widget into the stock bar layout. On a re-run it
# would fail on the existing directory, so update the checkout instead.
if [ -d "$PLUGIN_DIR/.git" ]; then
  echo "Updating $PLUGIN_ID..."
  omarchy plugin update "$PLUGIN_ID" --yes
else
  echo "Installing $PLUGIN_ID from $REPO_URL..."
  omarchy plugin add "$REPO_URL" --enable --yes
fi

[ -f "$PLUGIN_DIR/manifest.json" ] || {
  echo "ERROR: $PLUGIN_ID did not install to $PLUGIN_DIR" >&2
  exit 1
}

# Clone a built-in widget so Shibumi will accept it as a third-party one (see
# trap 2). omarchy-plugin-clone names the copy "<username>.<id>", refuses to
# overwrite, and rewrites the bar.layout entry -- keeping any per-widget
# settings on it -- so guard on the target and echo the id either way.
#
# A clone is a frozen copy: once Omarchy ships a new version of the widget the
# clone keeps running the old code, and if the shell's widget API moved under it
# the widget just errors out and silently vanishes from the bar. Unlike the
# omarchy.menu clone in install-omarchy-menu-websearch.sh these carry no local
# patch -- they are byte-identical copies -- so there is nothing to re-apply and
# we can simply re-clone whenever the Omarchy package version has moved. The
# stamp lives outside the plugin dir so it is never mistaken for plugin content.
STAMP_DIR="$HOME/.local/state/omarchy-supplement"

omarchy_version() {
  pacman -Q omarchy-dev 2>/dev/null || pacman -Q omarchy 2>/dev/null || echo unknown
}

clone_widget() {
  local source_id="$1" new_id target stamp want
  new_id="${USER:-$(id -un)}.${source_id#omarchy.}"
  target="$HOME/.config/omarchy/plugins/$new_id"
  stamp="$STAMP_DIR/$new_id.clonedfrom"
  want="$(omarchy_version)"

  if [ -d "$target" ] && [ "$(cat "$stamp" 2>/dev/null || true)" != "$want" ]; then
    # Stale (or first run since this check existed). Re-clone from the updated
    # /usr/share/omarchy. Removing the dir first is safe precisely because we
    # never edit these clones -- do NOT copy this to a clone you have patched.
    echo "  refreshing $new_id for $want..." >&2
    rm -rf "$target"
  fi
  if [ ! -d "$target" ]; then
    omarchy plugin clone "$source_id" >/dev/null
  fi
  mkdir -p "$STAMP_DIR"
  printf '%s\n' "$want" >"$stamp"
  printf '%s\n' "$new_id"
}

# ── Post-install: retire the old clock and center the new one ────────────────
bar_id="$(python3 -c "
import json
try:
    print(str(json.load(open('$SHELL_JSON')).get('bar', {}).get('id', '')))
except Exception:
    print('')
")"

case "$bar_id" in
hancore.shibumi.*)
  echo "Shibumi bar detected; rewriting its group layout..."
  weather_id="$(clone_widget omarchy.weather)"
  update_id="$(clone_widget omarchy.system-update)"
  python3 - "$SHELL_JSON" "$weather_id" "$update_id" <<'PY'
import json, os, shutil, sys, time

path, weather_id, update_id = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    cfg = json.load(fh)
before = json.dumps(cfg, sort_keys=True)

CLOCK = "G:promaa.clock"
# Composite pill that owns Shibumi's clock. Hidden, never removed -- trap 1.
CENTER_GROUP = "G8"
# Stock weather and update widgets, cloned past the alias blocklist -- trap 2.
EXTRAS = [(weather_id, {"unit": "metric"}), (update_id, {})]
# core/V2LayoutModel.js Limits / core/LayoutModel.js BaseCounts+ExtraLimits.
V2_MAX = {"left": 13, "center": 4, "right": 13}
V1_BASE = {"left": 7, "center": 1, "right": 7}
V1_MAX = {"left": 9, "center": 1, "right": 9}
REGIONS = ("left", "center", "right")

bar = cfg.setdefault("bar", {})
layout = bar.setdefault("layout", {})
for region in REGIONS:
    layout.setdefault(region, [])
sh = bar.setdefault("shibumi", {})
widgets = sh.setdefault("widgets", {})

# Shibumi's state service picks the live variant off shellStyle: "shibumi" is
# the v1 pill shell, anything else ("full", ...) is the v2 shell. The two keep
# separate layouts (order/v1SlotRoles/splits vs v2Layout) and separate
# per-group enable flags (enabledV1 vs enabledV2).
style = str(sh.get("presentation", {}).get("shellStyle") or "shibumi")
variant = "v1" if style == "shibumi" else "v2"


def entry_id(entry):
    return str(entry.get("id", "")) if isinstance(entry, dict) else str(entry or "")


def place_in_layout(plugin_id, region, settings=None):
    """Put a plugin in bar.layout, in this region, so the shell loads it.

    Shibumi arranges the bar from its own group layout, but a widget missing
    from bar.layout is never instantiated, so its group slot renders empty.

    The region is not cosmetic: Bar.qml builds its dynamic-widget specs from
    bar.layout and then reconciles v2Layout against them with followRegions,
    so a group whose bar.layout entry sits in a different region is moved back
    out of the one we put it in. Relocate the existing entry rather than
    leaving it where it was, and keep any settings already on it.
    """
    found = None
    for reg in REGIONS:
        keep = []
        for entry in layout[reg]:
            if entry_id(entry) == plugin_id:
                found = entry if isinstance(entry, dict) else {"id": plugin_id}
            else:
                keep.append(entry)
        layout[reg] = keep
    entry = found if found is not None else {"id": plugin_id}
    for key, value in (settings or {}).items():
        entry.setdefault(key, value)
    layout[region].append(entry)


def strip(seq, ids):
    return [x for x in seq if x not in ids]


group_cfg = widgets.setdefault(CENTER_GROUP, {})
extra_groups = ["G:" + plugin_id for plugin_id, _ in EXTRAS]

# v2 flanks the clock with these in the center; v1 has no room and keeps them
# on the right (see below). Placed in display order so bar.layout reads the
# same way the bar does.
extras_region = "center" if variant == "v2" else "right"
place_in_layout(EXTRAS[0][0], extras_region, EXTRAS[0][1])
place_in_layout("promaa.clock", "center")
place_in_layout(EXTRAS[1][0], extras_region, EXTRAS[1][1])

if variant == "v2":
    v2 = sh.setdefault("v2Layout", {})
    for region in REGIONS:
        v2.setdefault(region, [])
    moving = {CLOCK, CENTER_GROUP, *extra_groups}
    for region in REGIONS:
        v2[region] = strip(v2[region], moving)

    # Weather left of the clock, update dot right of it -- symmetric flanks so
    # the run stays centered on the clock (see the header note).
    center = [extra_groups[0], CLOCK, extra_groups[1]]
    if len(center) > V2_MAX["center"]:
        sys.exit("center run holds at most %d widgets" % V2_MAX["center"])
    v2["center"] = center

    # Rebuild the right run as everything already there plus the hidden G8,
    # parked last. Empty-string slots are Shibumi's own padding and are
    # restored afterwards up to the cap.
    right = [g for g in v2["right"] if g] + [CENTER_GROUP]
    if len(right) > V2_MAX["right"]:
        # No room on the right; park the hidden group on the left instead,
        # where the cap is the same but the run is usually shorter.
        right.remove(CENTER_GROUP)
        left = [g for g in v2["left"] if g] + [CENTER_GROUP]
        if len(left) > V2_MAX["left"]:
            sys.exit("no free Shibumi slot to park %s in" % CENTER_GROUP)
        v2["left"] = left + [""] * max(0, len(v2["left"]) - len(left))
    v2["right"] = right + [""] * max(
        0, min(V2_MAX["right"], len(v2["right"])) - len(right)
    )
    group_cfg["enabledV2"] = False
else:
    # v1 is rigid: 7+1+7 base slots hold exactly G1..G15, so the single center
    # slot is structurally reserved for G8 and a dynamic group can only live in
    # one of the two "extra" slots each side allows. Centering is impossible
    # here -- put the clock on the right and say so.
    order = sh.setdefault("order", {})
    for region in REGIONS:
        order.setdefault(region, [])
    moving = {CLOCK, *extra_groups}
    for region in REGIONS:
        order[region] = strip(order[region], moving)
    # Only two extra slots on the right, and the clock claims one of them.
    right = order["right"] + [CLOCK, extra_groups[0]]
    order["right"] = right[: V1_MAX["right"]]
    dropped = right[V1_MAX["right"] :]
    # v1SlotRoles and splits are parallel arrays the validator length-checks
    # against order: "base" for the fixed slots, "extra" past them, and one
    # split flag per gap between slots.
    roles = sh.setdefault("v1SlotRoles", {})
    splits = sh.setdefault("splits", {})
    splits.setdefault("boundaries", [False, False])
    for region in REGIONS:
        count = len(order[region])
        roles[region] = ["base"] * min(count, V1_BASE[region]) + ["extra"] * max(
            0, count - V1_BASE[region]
        )
        if region != "center":
            old = list(splits.get(region) or [])
            splits[region] = (old + [False] * count)[: max(0, count - 1)]
    group_cfg["enabledV1"] = False
    print("  note: Shibumi v1 shell style reserves the center slot for G8;")
    print("        the calendar clock was placed on the right instead.")
    for group in dropped:
        print("  note: no free v1 extra slot for %s; skipped." % group)

if json.dumps(cfg, sort_keys=True) == before:
    print("  shell.json already wired up; nothing to change.")
    sys.exit(0)

backup = "%s.bak.%d" % (path, int(time.time()))
shutil.copy2(path, backup)
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(cfg, fh, indent=2, sort_keys=True)
    fh.write("\n")
shutil.copymode(path, tmp)
os.replace(tmp, path)
print("  rewrote %s (backup: %s)" % (path, os.path.basename(backup)))
PY
  ;;
*)
  echo "Stock Omarchy bar detected; applying upstream's post-install steps..."
  # Guarded: `plugin disable` errors if the clock is already disabled, and
  # `bar move` errors if promaa.clock is already the center widget.
  omarchy plugin disable omarchy.clock >/dev/null 2>&1 || true
  omarchy bar move "$PLUGIN_ID" --section center >/dev/null 2>&1 || true
  # Pin it as the anchor so the bar does not shift as the clock resizes.
  # Unlike Shibumi, the stock bar really does honour centerAnchor.
  python3 - "$SHELL_JSON" "$PLUGIN_ID" <<'PY'
import json, os, shutil, sys, time

path, plugin_id = sys.argv[1], sys.argv[2]
with open(path) as fh:
    cfg = json.load(fh)
if cfg.get("bar", {}).get("centerAnchor") == plugin_id:
    sys.exit(0)
cfg.setdefault("bar", {})["centerAnchor"] = plugin_id
shutil.copy2(path, "%s.bak.%d" % (path, int(time.time())))
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(cfg, fh, indent=2, sort_keys=True)
    fh.write("\n")
shutil.copymode(path, tmp)
os.replace(tmp, path)
PY
  ;;
esac

# shell.json hot-reloads, so no restart is needed for the layout itself. Plugin
# *code* is only rescanned on request; do that so a fresh checkout is picked up
# without logging out. Non-fatal: omarchy-shell may simply not be running.
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

# The update widget is `visible: updateAvailable`, and it only re-runs
# omarchy-update-available on load and then every 6 hours. A rescan can leave it
# sitting at false, so it stays invisible for hours and reads as "the update dot
# never came back". Poke it once so it reflects reality immediately.
#
# The IPC target is the BUILT-IN id even for the clone: omarchy-plugin-clone
# deliberately leaves built-in ids inside plugin code as stable IPC targets and
# routes them via the manifest's clonedFrom.
qs -p /usr/share/omarchy/shell ipc call omarchy.system-update refresh >/dev/null 2>&1 || true

# ── Verify ───────────────────────────────────────────────────────────────────
# Read back what Shibumi settled on rather than what we wrote: its reconciler
# runs on the hot reload and will prune anything it rejects (trap 2), so a
# layout that looks right on disk a moment after writing is not proof.
sleep 2
python3 - "$SHELL_JSON" "$PLUGIN_ID" <<'PY'
import json, sys

path, plugin_id = sys.argv[1], sys.argv[2]
bar = json.load(open(path)).get("bar", {})
loaded = any(
    (entry.get("id") if isinstance(entry, dict) else entry) == plugin_id
    for region in ("left", "center", "right")
    for entry in bar.get("layout", {}).get(region, [])
)
if not loaded:
    sys.exit("ERROR: %s is not in bar.layout; the shell will not load it." % plugin_id)

sh = bar.get("shibumi")
if not str(bar.get("id", "")).startswith("hancore.shibumi") or not sh:
    print("Stock bar: centerAnchor = %s" % bar.get("centerAnchor"))
    raise SystemExit(0)

style = str(sh.get("presentation", {}).get("shellStyle") or "shibumi")
variant = "v1" if style == "shibumi" else "v2"
live = sh.get("order" if variant == "v1" else "v2Layout", {})
fixed = 15 if variant == "v1" else 18
seen = {g for region in ("left", "center", "right") for g in live.get(region, []) if g}
missing = ["G%d" % n for n in range(1, fixed + 1) if "G%d" % n not in seen]
if missing:
    sys.exit(
        "ERROR: %s missing from the Shibumi %s layout; it would silently reset "
        "to defaults. Restore from the newest .bak file beside %s."
        % (", ".join(missing), variant, path)
    )
if sh.get("widgets", {}).get("G8", {}).get("enabled%s" % variant.upper()) is not False:
    sys.exit("ERROR: Shibumi's G8 clock pill is still enabled.")
center = [g for g in live.get("center", []) if g]
if variant == "v2":
    if "G:promaa.clock" not in center:
        sys.exit("ERROR: the clock is not in the center run (%r)." % (center,))
    # Run-centered, so the clock only lands on the midpoint with equal flanks.
    left_of, right_of = center.index("G:promaa.clock"), len(center) - 1 - center.index(
        "G:promaa.clock"
    )
    if left_of != right_of:
        print(
            "  warning: %d widget(s) left of the clock, %d right; the run is "
            "centered as a whole, so the clock will sit off-center."
            % (left_of, right_of)
        )
print("  center run: %s" % " | ".join(center))
print("Shibumi %s layout: center = %s" % (variant, live.get("center")))
PY

# ── Sanity-check the feed config ─────────────────────────────────────────────
# Both of these fail *silently*: a top-level object makes fetch-events.py crash
# with an AttributeError nothing surfaces, and a Google web-UI URL fetches fine,
# returns HTML, parses to zero events and is reported as status "ok". The widget
# just shows an empty agenda either way, with nothing to suggest why.
python3 - "$HOME/.config/omarchy/calendars.json" <<'PY'
import json, os, sys
from urllib.parse import urlparse

path = sys.argv[1]
if not os.path.exists(path):
    raise SystemExit(0)
try:
    cfg = json.load(open(path))
except json.JSONDecodeError as exc:
    print("  warning: calendars.json is not valid JSON (%s)." % exc)
    raise SystemExit(0)

if not isinstance(cfg, list):
    print("  warning: calendars.json must be a JSON ARRAY of calendars, not a")
    print("           single object. Wrap the whole thing in [ ] or the fetcher")
    print("           crashes and the agenda stays empty.")
    raise SystemExit(0)

for cal in cfg:
    if not isinstance(cal, dict) or not cal.get("enabled", True):
        continue
    name = cal.get("name") or "<unnamed>"
    if cal.get("type") == "jmap" or cal.get("jmapUrl"):
        continue
    url = str(cal.get("url") or "")
    if not url:
        print("  warning: %r has no url yet." % name)
        continue
    parsed = urlparse(url)
    # The classic mistake: copying the browser address bar instead of Settings
    # and sharing -> Integrate calendar -> Secret address in iCal format. The
    # real feed is .../calendar/ical/<email>/private-<token>/basic.ics.
    if parsed.netloc == "calendar.google.com" and "/calendar/ical/" not in parsed.path:
        print("  warning: %r looks like the Google Calendar WEB PAGE url, not an" % name)
        print("           iCal feed -- it returns HTML, so you get 0 events and")
        print("           no error. Use Settings and sharing -> Integrate")
        print("           calendar -> Secret address in iCal format.")
PY

echo
echo "Calendar Sync clock installed."
echo "  Configure feeds via the widget's settings gear, or edit"
echo "  ~/.config/omarchy/calendars.json (hot-reloads, holds API tokens)."
echo "  Google API setup (shared/restricted calendars only):"
echo "    python3 $PLUGIN_DIR/google-auth.py"
