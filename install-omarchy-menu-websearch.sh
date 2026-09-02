#!/bin/bash

set -euo pipefail

# Make the Omarchy menu (SUPER+SPACE) fall back to a web search when a query
# matches no menu row and no installed app, instead of showing its dead
# "No matches for ..." card. Enter on that row opens the query in the default
# browser via omarchy-launch-browser.
#
# ── Why this is a clone-and-patch rather than a config edit ──────────────────
# The menu is the first-party `omarchy.menu` Quickshell plugin, and its search
# is a pure filter over menu items + .desktop entries with no fallback hook:
#   - ~/.config/omarchy/extensions/omarchy-menu.jsonc can only ADD rows, and
#     every row is subject to the same all-terms-must-match filter, so no static
#     row can be made to survive an arbitrary query.
#   - `provider` rows are limited to the provider names hardcoded in Menu.qml's
#     `providers` map; a user cannot register a new one.
# That leaves editing Menu.qml. Editing it in place under /usr/share/omarchy is
# out (pacman owns that tree and `omarchy update` reverts it), so we take the
# sanctioned route: `omarchy plugin clone`, i.e. a copy under
# ~/.config/omarchy/plugins/<user>.menu that shadows the built-in. The manifest
# records `omarchy.clonedFrom`, which makes the shell route every IPC call and
# keybinding aimed at `omarchy.menu` to the clone, so callers stay unchanged.
#
# ── Why the patch is applied here rather than vendored ──────────────────────
# A clone is a frozen copy of a ~1500-line QML file, so vendoring the whole
# thing in this repo would mean re-vendoring on every Omarchy release. Instead
# this script re-clones from whatever /usr/share/omarchy currently ships and
# re-applies two small anchored hunks on top. Re-run it after `omarchy update`
# to resync. If upstream ever moves the anchors the patch does NOT silently
# no-op -- the anchor assertions below fail the run loudly.

CLONE_SOURCE_ID="omarchy.menu"
STOCK_DIR="/usr/share/omarchy/shell/plugins/menu"
CLONE_ID="${USER:-$(id -un)}.menu"
CLONE_DIR="$HOME/.config/omarchy/plugins/$CLONE_ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

# Swap the search engine per machine without editing this script, e.g.
#   OMARCHY_MENU_SEARCH_URL='https://duckduckgo.com/?q=' \
#   OMARCHY_MENU_SEARCH_LABEL='DuckDuckGo' ./install-omarchy-menu-websearch.sh
SEARCH_URL="${OMARCHY_MENU_SEARCH_URL:-https://www.google.com/search?q=}"
SEARCH_LABEL="${OMARCHY_MENU_SEARCH_LABEL:-Google}"

UNINSTALL=0
case "${1:-}" in
  --uninstall) UNINSTALL=1 ;;
  -h | --help)
    echo "Usage: ./install-omarchy-menu-websearch.sh [--uninstall]"
    echo
    echo "  Clones the Omarchy menu plugin and patches it to offer a web search"
    echo "  when a query matches nothing. --uninstall removes the clone and"
    echo "  restores the built-in menu."
    exit 0
    ;;
  "") ;;
  *)
    echo "unknown option: $1" >&2
    exit 1
    ;;
esac

# Omarchy's bin dir is not guaranteed on PATH in a non-interactive run; without
# it the omarchy-* calls below silently no-op and the shell never restarts.
for d in "$HOME/.local/share/omarchy/bin" /usr/share/omarchy/bin; do
  [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH

for cmd in jq python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: $cmd is required." >&2
    exit 1
  }
done

# ── shell.json helpers ───────────────────────────────────────────────────────
# The shell decides a THIRD-PARTY plugin is enabled purely by whether its id is
# referenced in shell.json -- see isEnabled()/findEntryLocation() in
# /usr/share/omarchy/shell/services/PluginRegistry.qml. First-party plugins are
# the other way round: on by default, off only via disabledPlugins[]. So making
# the clone win needs both halves:
#     plugins[]         += {"id": "<user>.menu"}   -- turn the clone on
#     disabledPlugins[] += "omarchy.menu"          -- turn the built-in off
#
# Deliberately NOT via `omarchy plugin enable`: for a plugin that also declares
# a `bar-widget` kind (the menu does) that command enables it by PLACING IT IN
# THE BAR, which adds a launcher button the user never asked for. Referencing it
# in plugins[] enables the component without touching the bar layout.
edit_shell_json() {
  local filter="$1"
  shift
  local tmp
  tmp="$(mktemp "${SHELL_JSON}.XXXXXX")"
  jq "$@" "$filter" "$SHELL_JSON" >"$tmp"
  if cmp -s "$tmp" "$SHELL_JSON"; then
    rm -f "$tmp"
    return 1 # unchanged
  fi
  cp -a "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
  mv "$tmp" "$SHELL_JSON"
  return 0 # changed
}

restart_shell() {
  # No session means no running shell to talk to; the on-disk state is already
  # correct and the next login picks it up.
  [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || return 0
  # A plugin's QML is compiled once and cached: saving it triggers the shell's
  # "Local plugin changed, reloading" path and `rescanPlugins` returns fine, but
  # neither actually re-executes the new Menu.qml. Only a full restart does.
  # Not chained with `||` to a second restart command: omarchy-restart-shell
  # already kills every instance and relaunches one, and it exits non-zero
  # merely because it gives up polling after ~2s -- retrying on that would
  # restart a shell that is already on its way up.
  omarchy-restart-shell >/dev/null 2>&1 || true
  # It polls for the shell's own ping; plugin discovery finishes later, so wait
  # for the menu specifically rather than guessing with a fixed sleep.
  local attempt
  for ((attempt = 0; attempt < 40; attempt++)); do
    [ "$(omarchy-menu ping 2>/dev/null || true)" = "ok" ] && return 0
    sleep 0.5
  done
  return 0
}

# ── Uninstall ────────────────────────────────────────────────────────────────
if ((UNINSTALL)); then
  echo "Removing $CLONE_ID and restoring the built-in menu..."
  rm -rf "$CLONE_DIR"
  if [ -f "$SHELL_JSON" ]; then
    edit_shell_json '
      .plugins = ((.plugins // []) | map(select(.id != $id)))
      | .disabledPlugins = ((.disabledPlugins // []) | map(select(. != $src)))
      | .cloneSourceRestores = ((.cloneSourceRestores // []) | map(select(. != $id)))
      | del(.plugins           | select(length == 0))
      | del(.disabledPlugins   | select(length == 0))
      | del(.cloneSourceRestores | select(length == 0))
    ' --arg id "$CLONE_ID" --arg src "$CLONE_SOURCE_ID" || true
  fi
  restart_shell
  echo "Done. The built-in $CLONE_SOURCE_ID is active again."
  exit 0
fi

[ -f "$STOCK_DIR/Menu.qml" ] || {
  echo "ERROR: $STOCK_DIR/Menu.qml not found -- this needs Omarchy 4 (quattro)." >&2
  exit 1
}
[ -f "$SHELL_JSON" ] || {
  echo "ERROR: $SHELL_JSON not found." >&2
  exit 1
}

# ── The patch ────────────────────────────────────────────────────────────────
# `apply` inserts two marked hunks; `strip` removes them again. strip is the
# exact inverse, which is what lets the sync check below ask "is this clone just
# the current stock file plus our patch?" without storing a copy of stock.
patch_qml() {
  python3 - "$1" "$2" "$3" "$SEARCH_URL" "$SEARCH_LABEL" <<'PY'
import re, sys

mode, src_path, dst_path, search_url, search_label = sys.argv[1:6]

START = "  // >>> omarchy-supplement: web-search fallback"
END = "  // <<< omarchy-supplement: web-search fallback"
TAIL = "// omarchy-supplement: web-search fallback"

# Insert the helper just above this function, i.e. immediately after runAction().
ANCHOR_HELPER = "  function rowHeightForDetail(detail) {"
# Append the fallback right after menu rows and app rows have both been scored
# and concatenated, so it only fires when genuinely nothing matched.
ANCHOR_CALL = "      rows = currentRows.concat(drilldownRows)\n"

src = open(src_path, encoding="utf-8").read()

if mode == "strip":
    src = re.sub(
        re.escape(START) + r"\n(?:.*\n)*?" + re.escape(END) + r"\n\n?",
        "", src,
    )
    src = re.sub(r"^.*" + re.escape(TAIL) + r"\n", "", src, flags=re.M)
    open(dst_path, "w", encoding="utf-8").write(src)
    sys.exit(0)

for name, anchor in (("helper", ANCHOR_HELPER), ("call site", ANCHOR_CALL)):
    n = src.count(anchor)
    if n != 1:
        sys.stderr.write(
            "ERROR: the %s anchor was found %d times in Menu.qml (expected 1).\n"
            "Upstream Omarchy has changed the menu; update the anchors in\n"
            "install-omarchy-menu-websearch.sh before re-running.\n" % (name, n)
        )
        sys.exit(2)

# The row is handed to a QML ListModel alongside rows built by
# MenuModel.displayRow(), so it must carry exactly the same 15 fields in the
# same order -- the delegate declares each of them as a `required property`.
# kind "action" is what makes Enter run `action` instead of descending a submenu.
helper = """%(start)s
  readonly property string webSearchPrefix: "%(url)s"

  function webSearchRow(query) {
    var url = root.webSearchPrefix + encodeURIComponent(query)
    return {
      itemId: "websearch",
      kind: "action",
      icon: "",
      iconFont: "",
      appIcon: "",
      appId: "",
      label: "%(label)s “" + query + "”",
      target: "",
      detail: "",
      path: "",
      childCount: 0,
      action: "omarchy-launch-browser " + Util.shellQuote(url),
      provider: "",
      score: 0,
      section: ""
    }
  }
%(end)s

""" % {"start": START, "end": END, "url": search_url, "label": search_label}

call = "      if (rows.length === 0) rows.push(root.webSearchRow(query))  %s\n" % TAIL

src = src.replace(ANCHOR_HELPER, helper + ANCHOR_HELPER, 1)
src = src.replace(ANCHOR_CALL, ANCHOR_CALL + call, 1)
open(dst_path, "w", encoding="utf-8").write(src)
PY
}

# ── Is the existing clone still in sync with the shipped menu? ───────────────
# Strip our hunks back out and compare the whole tree against stock. Any drift
# (an Omarchy update changed the menu, or the clone was hand-edited) means the
# clone is stale, so re-clone rather than patch a copy of an old menu.
clone_is_current() {
  [ -d "$CLONE_DIR" ] || return 1
  local stripped
  stripped="$(mktemp)"
  patch_qml strip "$CLONE_DIR/Menu.qml" "$stripped" 2>/dev/null || {
    rm -f "$stripped"
    return 1
  }
  cmp -s "$stripped" "$STOCK_DIR/Menu.qml" || {
    rm -f "$stripped"
    return 1
  }
  rm -f "$stripped"
  # Everything except Menu.qml (patched) and manifest.json (re-identified) must
  # match stock byte for byte.
  local f name
  for f in "$STOCK_DIR"/*; do
    name="${f##*/}"
    [ "$name" = "Menu.qml" ] && continue
    [ "$name" = "manifest.json" ] && continue
    cmp -s "$f" "$CLONE_DIR/$name" || return 1
  done
  # And the clone must not have picked up files a newer stock release dropped.
  for f in "$CLONE_DIR"/*; do
    name="${f##*/}"
    [ "$name" = "manifest.json" ] && continue
    [ -e "$STOCK_DIR/$name" ] || return 1
  done
  return 0
}

if clone_is_current; then
  echo "$CLONE_ID is already a current clone of $CLONE_SOURCE_ID; re-applying patch."
else
  if [ -e "$CLONE_DIR" ]; then
    # Backups go OUTSIDE ~/.config/omarchy/plugins: everything in there is
    # scanned as a plugin, and a stale copy still declaring id "<user>.menu"
    # would collide with the live one.
    backup_dir="$HOME/.local/state/omarchy-supplement"
    mkdir -p "$backup_dir"
    backup="$backup_dir/$CLONE_ID.bak.$(date +%s)"
    echo "$CLONE_DIR is stale (Omarchy updated, or it was edited); backing it up to $backup"
    mv "$CLONE_DIR" "$backup"
  fi
  echo "Cloning $CLONE_SOURCE_ID -> $CLONE_ID"
  mkdir -p "$(dirname "$CLONE_DIR")"
  # Done by hand rather than via `omarchy plugin clone` so this works with no
  # running shell (that command talks IPC and fails without one), and so it
  # never enables the clone as a bar widget. The manifest rewrite mirrors what
  # omarchy-plugin-clone writes, `omarchy.clonedFrom` included -- that key is
  # what makes the shell route omarchy.menu IPC to this copy.
  stage="$(mktemp -d "$(dirname "$CLONE_DIR")/.clone.XXXXXX")"
  cp -aL "$STOCK_DIR/." "$stage/"
  jq --arg id "$CLONE_ID" --arg src "$CLONE_SOURCE_ID" --arg name "My Omarchy menu" '
    .id = $id
    | .name = $name
    | (if (.barWidget | type) == "object" then .barWidget.displayName = $name else . end)
    | .omarchy = ((if (.omarchy | type) == "object" then .omarchy else {} end) + { clonedFrom: $src })
    | del(.omarchy.clonePaths)
  ' "$STOCK_DIR/manifest.json" >"$stage/manifest.json"
  mv "$stage" "$CLONE_DIR"
fi

# Strip first, unconditionally: on a re-run against an already-patched clone a
# bare apply would insert a SECOND copy of the helper (the anchor it keys off
# is still there, above both), and QML rejects the duplicate property/function
# declarations -- which takes the whole menu plugin down, not just the fallback.
stripped="$(mktemp)"
patched="$(mktemp)"
patch_qml strip "$CLONE_DIR/Menu.qml" "$stripped"
patch_qml apply "$stripped" "$patched"
rm -f "$stripped"
mv "$patched" "$CLONE_DIR/Menu.qml"
chmod 644 "$CLONE_DIR/Menu.qml"
echo "Patched $CLONE_DIR/Menu.qml (search: $SEARCH_LABEL -> $SEARCH_URL)"

# ── Point the shell at the clone ─────────────────────────────────────────────
if edit_shell_json '
  .plugins = ((.plugins // []) | if any(.[]; .id == $id) then . else . + [{id: $id}] end)
  | .disabledPlugins = ((.disabledPlugins // []) | if index($src) then . else . + [$src] end)
  | .cloneSourceRestores = ((.cloneSourceRestores // []) | if index($id) then . else . + [$id] end)
' --arg id "$CLONE_ID" --arg src "$CLONE_SOURCE_ID"; then
  echo "Enabled $CLONE_ID in $SHELL_JSON (built-in $CLONE_SOURCE_ID disabled)"
else
  echo "$SHELL_JSON already points at $CLONE_ID"
fi

restart_shell

# ── Verify ───────────────────────────────────────────────────────────────────
# The patch marker proves the hunks landed; `omarchy menu ping` proves a menu
# plugin is actually enabled and loaded (it answers "unknown" when none is), and
# it is routed through the same clonedFrom lookup the keybinding uses.
grep -q "omarchy-supplement: web-search fallback" "$CLONE_DIR/Menu.qml" || {
  echo "ERROR: the patch is missing from $CLONE_DIR/Menu.qml." >&2
  exit 1
}
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  if [ "$(omarchy-menu ping 2>/dev/null || true)" != "ok" ]; then
    echo "ERROR: the menu did not come back after the restart. Check:" >&2
    echo "  omarchy-shell shell listPlugins | jq '.[] | select(.id | test(\"menu\"))'" >&2
    exit 1
  fi
fi

cat <<EOF

Done. Open the menu (SUPER+SPACE) and type something that matches no menu item
and no installed app -- e.g. "hyprland scratchpad" -- and the top row becomes
$SEARCH_LABEL "<your query>". Enter opens it in your default browser.

Re-run this script after 'omarchy update' to re-clone the refreshed menu and
re-apply the patch. Revert with:
  ./install-omarchy-menu-websearch.sh --uninstall
EOF
