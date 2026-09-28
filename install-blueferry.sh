#!/bin/bash

set -euo pipefail

# Install BlueFerry -- an iPhone's SMS, RCS and iMessage on the Linux desktop
# over Bluetooth, with no Mac relay, Apple login, or cloud service.
#   Upstream:   https://github.com/erikwb/blueferry
#   Bar widget: https://github.com/erikwb/omarchy-blueferry
#
# It is three Bluetooth profiles behind one unprivileged per-user backend that
# publishes a session D-Bus API: MAP (messages, read state, sends) and PBAP
# (contacts) over Classic, ANCS over LE for iPhone system notifications and the
# group-message metadata that makes a group chat look like one.
#
# NOT IN THE AUR. Upstream ships split pacman packages on GitHub Releases, so
# this installer resolves the latest tag from the API and `pacman -U`s the
# .pkg.tar.zst assets it names. Unlike install-strata.sh there is no version
# stamp to keep: these are real packages, so `pacman -Q` is the source of truth
# for what is installed and pacman owns upgrade/removal bookkeeping.
#
# Integrity: the release carries no signatures and no checksum file, but the
# GitHub API reports a `digest` per asset, and that is verified after download
# (fatal on mismatch). That catches a corrupted or truncated transfer, not a
# compromised release -- for a trust root you control, build from the git
# checkout instead:  BLUEFERRY_FROM_SOURCE=1 ./install-blueferry.sh
#
# Overridable per machine:
#   BLUEFERRY_CLIENTS="gtk quickshell"  which client packages to install
#                                       (backend is always installed; "qt"
#                                       adds the Kirigami client and drags in
#                                       pyside6 + kirigami)
#   BLUEFERRY_BAR_WIDGET=0              skip the Omarchy bar plugin
#   BLUEFERRY_FROM_SOURCE=1             clone and ./build.sh -si instead
#
# THE PART THAT SURPRISES PEOPLE: installing/upgrading blueferry-backend
# RESTARTS bluetooth.service (its .install hook plus an ALPM hook, to apply the
# `bluetoothd -E` drop-in that BlueZ needs for per-bearer connects). Any active
# Bluetooth device -- headphones, mouse -- drops for a moment. That is upstream
# behaviour, not something this script adds; it is only noted here because a
# provision run is exactly when you won't be expecting it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="erikwb/blueferry"
SRC_DIR="$HOME/.local/share/blueferry-src"
PLUGIN_REPO_URL="https://github.com/erikwb/omarchy-blueferry.git"
PLUGIN_ID="io.weirdware.blueferry"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
CONFIG_DIR="$HOME/.config/blueferry"
LOCAL_ENV="$CONFIG_DIR/local.env"
LOCAL_ENV_TEMPLATE="$SCRIPT_DIR/blueferry/local.env"
MIN_BLUEZ="5.86"

# Omarchy's bin dir is not guaranteed on PATH in a non-interactive run; without
# it the plugin/shell calls at the end would silently do nothing.
for d in "$HOME/.local/share/omarchy/bin" /usr/share/omarchy/bin; do
  [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH

read -r -a CLIENTS <<<"${BLUEFERRY_CLIENTS:-gtk quickshell}"
PACKAGES=(blueferry-backend)
for client in "${CLIENTS[@]}"; do
  case "$client" in
    gtk | qt | quickshell) PACKAGES+=("blueferry-$client") ;;
    "") ;;
    *) echo "install-blueferry: unknown client '$client' (want gtk|qt|quickshell)" >&2; exit 1 ;;
  esac
done

# ── Preconditions ────────────────────────────────────────────────────────────
# The backend hard-depends on bluez>=5.86 (the first release with working
# per-bearer connection methods), so an out-of-date machine would fail deep
# inside pacman's dependency resolution with nothing pointing at the cause.
bluez_version="$(pacman -Q bluez 2>/dev/null | awk '{print $2}')"
if [ -z "$bluez_version" ]; then
  echo "install-blueferry: bluez is not installed; pacman will pull it in." >&2
elif (($(vercmp "$bluez_version" "$MIN_BLUEZ") < 0)); then
  echo "ERROR: BlueFerry's backend needs bluez >= $MIN_BLUEZ; this machine has $bluez_version." >&2
  echo "       Run a full 'sudo pacman -Syu' first." >&2
  exit 1
fi

pkg_version() { pacman -Q "$1" 2>/dev/null | awk '{print $2}'; }

# ── Source build (opt-in) ────────────────────────────────────────────────────
if [ "${BLUEFERRY_FROM_SOURCE:-0}" != 0 ]; then
  # build.sh snapshots the working tree, runs the linters and the full
  # device-isolated test suite, then makepkg -si's all four split packages, so
  # this path is minutes not seconds and pulls in every checkdepend.
  #
  # It also forces /usr/bin/python explicitly, which matters here: this fleet
  # installs mise (install-mise.sh), whose shim python would otherwise decide
  # the site-packages directory the package installs into -- producing a
  # package for an interpreter that isn't the one running the daemon.
  # Guarded so a re-run on a provisioned machine never reaches for sudo (and
  # so can't fail non-interactively inside install-all.sh).
  command -v makepkg >/dev/null || sudo pacman -S --noconfirm --needed base-devel python
  if [ -d "$SRC_DIR/.git" ]; then
    git -C "$SRC_DIR" pull --ff-only
  else
    git clone "https://github.com/$REPO.git" "$SRC_DIR"
  fi
  (cd "$SRC_DIR" && ./build.sh -si)
else
  # ── Resolve the latest release ─────────────────────────────────────────────
  # Everything downloaded lands in one mktemp -d, cleared on exit.
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  have_release=1
  if ! curl -fsSL --retry 2 -o "$tmpdir/release.json" \
    "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null; then
    have_release=0
    if [ -n "$(pkg_version blueferry-backend)" ]; then
      echo "install-blueferry: cannot reach the GitHub API; keeping the installed version." >&2
    else
      echo "ERROR: cannot reach the GitHub API and BlueFerry is not installed." >&2
      exit 1
    fi
  fi

  if ((have_release)); then
    # Emit one "pkgname version filename url sha256" line per wanted asset.
    # Read from the API's own asset list rather than composing URLs: the
    # pkgrel is part of the file name and only the release knows it.
    mapfile -t wanted_assets < <(
      python3 - "$tmpdir/release.json" "${PACKAGES[@]}" <<'PY'
import json, re, sys

path, wanted = sys.argv[1], sys.argv[2:]
with open(path) as handle:
    data = json.load(handle)
found = {}
for asset in data.get("assets", []):
    match = re.fullmatch(
        r"(blueferry-[a-z]+)-(\d[^-]*-\d+)-any\.pkg\.tar\.zst", asset["name"]
    )
    if not match:
        continue
    # The API reports "sha256:<hex>" per asset; the release carries no
    # signature and no checksum file, so this is the only integrity handle.
    digest = str(asset.get("digest") or "")
    found[match.group(1)] = (
        match.group(2),
        asset["name"],
        asset["browser_download_url"],
        digest.split(":", 1)[1] if digest.startswith("sha256:") else "-",
    )
tag = data.get("tag_name", "?")
for name in wanted:
    # Fields: pkgname version filename url sha256, or MISSING <pkgname> <tag>.
    if name in found:
        print(name, *found[name])
    else:
        print("MISSING", name, tag, "-", "-")
PY
    )

    downloads=()

    for line in "${wanted_assets[@]}"; do
      read -r pkg version filename url sha256 <<<"$line"
      if [ "$pkg" = MISSING ]; then
        # A client package this release does not carry (blueferry-quickshell is
        # Arch-only) is a skip, not a failure. Fields shift by one on this line:
        # $version holds the package name and $filename the release tag.
        echo "install-blueferry: $version is not in release $filename; skipping it." >&2
        continue
      fi
      if [ "$(pkg_version "$pkg")" = "$version" ]; then
        echo "  $pkg $version already installed."
        continue
      fi
      echo "  downloading $filename..."
      curl -fsSL --retry 2 -o "$tmpdir/$filename" "$url"
      if [ "$sha256" != "-" ]; then
        actual="$(sha256sum "$tmpdir/$filename" | awk '{print $1}')"
        if [ "$actual" != "$sha256" ]; then
          echo "ERROR: checksum mismatch for $filename" >&2
          echo "       expected $sha256" >&2
          echo "       got      $actual" >&2
          exit 1
        fi
      else
        echo "  warning: the API reported no digest for $filename; not verified." >&2
      fi
      downloads+=("$tmpdir/$filename")
    done

    if ((${#downloads[@]})); then
      echo "Installing ${#downloads[@]} BlueFerry package(s) (bluetooth.service will restart)..."
      # --needed is honoured by -U as well as -S, so a re-run that raced
      # another install is a no-op rather than a reinstall.
      sudo pacman -U --noconfirm --needed "${downloads[@]}"
    else
      echo "BlueFerry packages already current."
    fi
  fi
fi

command -v blueferry >/dev/null || {
  echo "ERROR: blueferry did not install; /usr/bin/blueferry is missing." >&2
  exit 1
}

# ── Seed the local settings file ─────────────────────────────────────────────
# Real file, 0600, inside a 0700 directory -- see the header of
# blueferry/local.env for why this is seeded rather than stowed (BlueFerry
# reads it with O_NOFOLLOW, so a stow symlink is silently ignored, and its
# existence is what satisfies blueferry.service's ConditionPathExists).
#
# Seeded only when absent: after the first pairing this file also holds the
# phone's MAC, and BlueFerry rewrites it from parsed key=value pairs, so
# re-copying the template would both clobber the pairing and be pointless (the
# comments are already gone by then).
install -d -m 700 "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
if [ -L "$LOCAL_ENV" ]; then
  echo "install-blueferry: WARNING -- $LOCAL_ENV is a symlink." >&2
  echo "  BlueFerry opens it with O_NOFOLLOW and will silently ignore every" >&2
  echo "  setting in it. Replace it with a real file. Not repaired here, in" >&2
  echo "  case it points at something you meant to keep." >&2
elif [ ! -e "$LOCAL_ENV" ]; then
  install -m 600 "$LOCAL_ENV_TEMPLATE" "$LOCAL_ENV"
  echo "Seeded $LOCAL_ENV from the repo template."
else
  chmod 600 "$LOCAL_ENV"
  echo "Kept the existing $LOCAL_ENV (BlueFerry owns it once paired)."
fi

# The vendor unit is enabled for every user via
# /usr/lib/systemd/user/default.target.wants, so there is nothing to enable
# here -- just make sure systemd has seen it. Not started: the clients
# D-Bus-activate the backend on demand, and it starts at the next login now
# that local.env exists.
systemctl --user daemon-reload 2>/dev/null || true

# ── Omarchy bar widget ───────────────────────────────────────────────────────
# The panel is a separate repo, and it drives the Quickshell client, so it is
# pointless without that package.
if [ "${BLUEFERRY_BAR_WIDGET:-1}" != 0 ] \
  && command -v omarchy >/dev/null 2>&1 \
  && [ -n "$(pkg_version blueferry-quickshell)" ]; then

  if [ -d "$PLUGIN_DIR/.git" ]; then
    echo "Updating the $PLUGIN_ID bar plugin..."
    omarchy plugin update "$PLUGIN_ID" --yes
  else
    echo "Installing the $PLUGIN_ID bar plugin..."
    # Omarchy adds third-party plugins disabled; --enable also drops it into
    # bar.layout, which is what actually makes the shell instantiate it.
    omarchy plugin add "$PLUGIN_REPO_URL" --enable --yes
  fi

  [ -f "$PLUGIN_DIR/manifest.json" ] || {
    echo "ERROR: $PLUGIN_ID did not install to $PLUGIN_DIR" >&2
    exit 1
  }

  # On a Shibumi bar (install-shibumi.sh) bar.layout only decides which plugins
  # get *loaded*; the arrangement comes from bar.shibumi.v2Layout (or .order in
  # the v1 pill style), where a third-party widget is the entry "G:<plugin id>".
  # Without that entry the plugin loads and renders nowhere -- which reads
  # exactly like "the widget is broken".
  #
  # Two invariants from install-sync-calendar.sh's header apply here too, and
  # both fail silently: every fixed group G1..G18 must stay in the layout or
  # Shibumi discards the whole thing and falls back to its built-in default,
  # and the run caps (13 per side) are enforced by the same validator. This
  # only ever appends, so nothing is at risk of being dropped.
  python3 - "$SHELL_JSON" "$PLUGIN_ID" <<'PY'
import json, os, shutil, sys, time

path, plugin_id = sys.argv[1], sys.argv[2]
group = "G:" + plugin_id
REGIONS = ("left", "center", "right")
V2_MAX = {"left": 13, "center": 4, "right": 13}
V1_BASE = {"left": 7, "center": 1, "right": 7}
V1_MAX = {"left": 9, "center": 1, "right": 9}
V1_DEFAULT = {
    "left": ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
    "center": ["G8"],
    "right": ["G9", "G10", "G11", "G14", "G12", "G13", "G15"],
}

try:
    with open(path) as handle:
        cfg = json.load(handle)
except (OSError, ValueError) as error:
    print("  note: could not read %s (%s); bar layout left alone." % (path, error))
    raise SystemExit(0)
before = json.dumps(cfg, sort_keys=True)

bar = cfg.setdefault("bar", {})
layout = bar.setdefault("layout", {})
for region in REGIONS:
    layout.setdefault(region, [])


def entry_id(entry):
    return str(entry.get("id", "")) if isinstance(entry, dict) else str(entry or "")


# bar.layout: keep exactly one entry, in the right-hand region. The region is
# not cosmetic -- Bar.qml reconciles the group layout against bar.layout with
# followRegions, so a group whose bar.layout entry sits elsewhere is moved back
# out of the region we put it in.
#
# Already in the right region: leave it where it is, so a re-run does not keep
# shuffling the widget to the end (and, on v2, to the last slot below).
already_placed = any(entry_id(e) == plugin_id for e in layout["right"])
if not already_placed:
    existing = None
    for region in REGIONS:
        keep = []
        for entry in layout[region]:
            if entry_id(entry) == plugin_id:
                existing = entry if isinstance(entry, dict) else {"id": plugin_id}
            else:
                keep.append(entry)
        layout[region] = keep
    layout["right"].append(existing if existing is not None else {"id": plugin_id})

# Since Shibumi 0.1.1-beta.14 its settings live in the hancore.shibumi.state
# entry of the top-level plugins array; bar.shibumi is a stale pre-beta.14 copy
# the runtime ignores. Reading it made a v2 ("full") machine look like v1 (it
# has no presentation key, so shellStyle fell back to "shibumi") and sent it
# down the v1 path. Use the live block; fall back only on pre-beta.14 installs.
_state = next((p for p in cfg.get("plugins") or [] if isinstance(p, dict) and p.get("id") == "hancore.shibumi.state"), None)
sh = _state.get("shibumi") if _state is not None else bar.get("shibumi")
if str(bar.get("id", "")).startswith("hancore.shibumi") and isinstance(sh, dict):
    style = str(sh.get("presentation", {}).get("shellStyle") or "shibumi")
    if style != "shibumi":
        v2 = sh.setdefault("v2Layout", {})
        for region in REGIONS:
            v2.setdefault(region, [])
        if already_placed and group in v2["right"]:
            # Already has its slot; keep it (see already_placed above).
            print("  %s already placed on the right of the bar." % plugin_id)
            raise SystemExit(0)
        for region in REGIONS:
            v2[region] = [g for g in v2[region] if g != group]
        # Empty strings are Shibumi's own padding slots; collapse them, append,
        # then pad back out to the run's previous length.
        right = [g for g in v2["right"] if g]
        padding = max(0, min(V2_MAX["right"], len(v2["right"])) - len(right) - 1)
        if len(right) >= V2_MAX["right"]:
            # Nothing written: the plugin is already loaded via bar.layout, it
            # just has no slot to draw in. Better than evicting someone else's.
            print(
                "  note: the Shibumi right run is full (%d/%d); place %s by hand"
                " from Setup > Plugins." % (len(right), V2_MAX["right"], group)
            )
            raise SystemExit(0)
        v2["right"] = right + [group] + [""] * padding
    else:
        # v1 is rigid: 7+1+7 base slots hold G1..G15 exactly, and a dynamic
        # group can only occupy one of the two "extra" slots each side allows.
        # Shibumi only writes `order` once the layout has been edited; until
        # then it runs on LayoutModel.js defaultOrder(). Building from [] would
        # leave G1..G15 out and the validator would reset the whole bar, so
        # start from that default (keeping dynamic groups) if any is absent.
        order = sh.get("order") if isinstance(sh.get("order"), dict) else {}
        present = {g for region in REGIONS for g in (order.get(region) or [])}
        if not all("G%d" % n in present for n in range(1, 16)):
            order = {
                region: V1_DEFAULT[region]
                + [g for g in (order.get(region) or []) if str(g).startswith("G:")]
                for region in REGIONS
            }
        sh["order"] = order
        for region in REGIONS:
            order[region] = [g for g in order[region] if g != group]
        if len(order["right"]) >= V1_MAX["right"]:
            print("  note: no free Shibumi v1 extra slot for %s; skipped." % group)
            raise SystemExit(0)
        order["right"].append(group)
        # v1SlotRoles and splits are parallel arrays the validator
        # length-checks against order.
        roles = sh.setdefault("v1SlotRoles", {})
        splits = sh.setdefault("splits", {})
        splits.setdefault("boundaries", [False, False])
        for region in REGIONS:
            count = len(order[region])
            roles[region] = ["base"] * min(count, V1_BASE[region]) + ["extra"] * max(
                0, count - V1_BASE[region]
            )
            if region != "center":
                splits[region] = (list(splits.get(region) or []) + [False] * count)[
                    : max(0, count - 1)
                ]

if json.dumps(cfg, sort_keys=True) == before:
    print("  bar layout already has %s; nothing to change." % plugin_id)
    sys.exit(0)

backup = "%s.bak.%d" % (path, int(time.time()))
shutil.copy2(path, backup)
tmp = path + ".tmp"
with open(tmp, "w") as handle:
    json.dump(cfg, handle, indent=2, sort_keys=True)
    handle.write("\n")
shutil.copymode(path, tmp)
os.replace(tmp, path)
print("  placed %s on the right of the bar (backup: %s)" % (plugin_id, os.path.basename(backup)))
PY

  # shell.json hot-reloads, but plugin *code* is only re-read on request.
  # Non-fatal: omarchy-shell may simply not be running.
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

  # Read back what Shibumi settled on rather than what we wrote -- its
  # reconciler runs on the hot reload and prunes anything it rejects.
  sleep 2
  python3 - "$SHELL_JSON" "$PLUGIN_ID" <<'PY'
import json, sys

path, plugin_id = sys.argv[1], sys.argv[2]
try:
    cfg = json.load(open(path))
    bar = cfg.get("bar", {})
except (OSError, ValueError):
    raise SystemExit(0)
loaded = any(
    (entry.get("id") if isinstance(entry, dict) else entry) == plugin_id
    for region in ("left", "center", "right")
    for entry in bar.get("layout", {}).get(region, [])
)
if not loaded:
    print("  warning: %s is not in bar.layout; the shell will not load it." % plugin_id)
    raise SystemExit(0)
# Since Shibumi 0.1.1-beta.14 its settings live in the hancore.shibumi.state
# entry of the top-level plugins array; bar.shibumi is a stale pre-beta.14 copy
# the runtime ignores. Reading it made a v2 ("full") machine look like v1 (it
# has no presentation key, so shellStyle fell back to "shibumi") and sent it
# down the v1 path. Use the live block; fall back only on pre-beta.14 installs.
_state = next((p for p in cfg.get("plugins") or [] if isinstance(p, dict) and p.get("id") == "hancore.shibumi.state"), None)
sh = _state.get("shibumi") if _state is not None else bar.get("shibumi")
if not isinstance(sh, dict):
    raise SystemExit(0)
style = str(sh.get("presentation", {}).get("shellStyle") or "shibumi")
variant = "v1" if style == "shibumi" else "v2"
live = sh.get("order" if variant == "v1" else "v2Layout", {})
fixed = 15 if variant == "v1" else 18
seen = {g for region in ("left", "center", "right") for g in live.get(region, []) if g}
missing = ["G%d" % n for n in range(1, fixed + 1) if "G%d" % n not in seen]
if missing:
    sys.exit(
        "  ERROR: %s missing from the Shibumi %s layout; it would silently reset to"
        " defaults. Restore the newest .bak beside %s." % (", ".join(missing), variant, path)
    )
if ("G:" + plugin_id) not in seen:
    print("  warning: Shibumi pruned G:%s from its %s layout." % (plugin_id, variant))
else:
    print("  Shibumi %s right run: %s" % (variant, " | ".join(g for g in live.get("right", []) if g)))
PY
elif [ "${BLUEFERRY_BAR_WIDGET:-1}" != 0 ]; then
  echo "install-blueferry: skipping the bar widget (needs the omarchy CLI and blueferry-quickshell)."
fi

# ── Verify ───────────────────────────────────────────────────────────────────
for binary in blueferry blueferry-tui; do
  command -v "$binary" >/dev/null || echo "  warning: $binary is not on PATH." >&2
done

cat <<EOF

BlueFerry $(pkg_version blueferry-backend) installed. Clients: ${CLIENTS[*]:-none}

Pairing is interactive and has to happen on this machine, with the phone in
hand. Keep the iPhone unlocked on Settings > Bluetooth, then run one of:

    blueferry-gtk           # GTK client, also bound to SUPER+M
    blueferry pair-setup    # same wizard in the terminal

Scan, select the iPhone, Pair, and confirm the code on both sides (it can take
~15s to appear). Then tap the (i) beside this computer on the phone and enable
"Show Message Notifications" and "Sync Contacts" -- if those toggles are
missing, back out to the device list and reopen the (i) page a few times. Also
approve "Allow System Notifications" and the desktop wallet prompt.

Diagnostics:  blueferry doctor  |  journalctl --user -u blueferry -f
EOF
