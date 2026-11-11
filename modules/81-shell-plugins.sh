#!/bin/bash
# Non-bar shell plugins: QuickSwitch (SUPER+TAB), OmaDock, Spotlight, Altscape (ALT+TAB)
source "$(dirname "$0")/../lib/common.sh"

# These are overlays and services, enabled through shell.json's `plugins` array
# and never placed on the bar. Their Hyprland binds and window rules live in
# config/hypr/quickswitch.lua and config/hypr/apps.lua, each guarded on the
# plugin being installed -- so Hyprland is reloaded at the end to pick them up.
# Settings an app rewrites on save are seeded from config/plugins/seeds once.
# Skip some on one machine with:  SHELL_PLUGINS_SKIP="omadock" ./setup shell-plugins

SKIP=" ${SHELL_PLUGINS_SKIP:-} "
skipped() { [[ $SKIP == *" $1 "* ]]; }
FAILED=0

# Add (enabled) or fast-forward a git plugin. `plugin update` doesn't re-enable,
# and a plugin missing from shell.json loads for nobody, so enable every time.
# (No --yes on enable: its second argument is a bar placement.)
git_plugin() {
  local id="$1" url="$2"
  if [ -d "$PLUGINS_DIR/$id/.git" ]; then
    omarchy plugin update "$id" --yes || warn "update of $id failed; keeping the installed version"
  elif [ -e "$PLUGINS_DIR/$id" ]; then
    note "$id is installed but not from git; leaving it as is"
  else
    omarchy plugin add "$url" --enable --yes || { warn "could not add $id"; FAILED=1; return 1; }
  fi
  omarchy plugin enable "$id" >/dev/null 2>&1 || true
}

# QuickSwitch: macOS-style switcher with window snapshots. Hold SUPER, tap TAB
# or the arrows, release to switch; SUPER+Q quits the highlighted app.
if ! skipped ewweberlin.quickswitch; then
  step "QuickSwitch"
  git_plugin ewweberlin.quickswitch https://github.com/ewweberlin/QuickSwitch.git || true
fi

# OmaDock: macOS-style dock.
if ! skipped omadock; then
  step "OmaDock"
  seed "$CONFIG/plugins/seeds/omadock.json" "$HOME/.config/omarchy/omadock.json"
  git_plugin omadock https://github.com/thepathless/omadock.git || true
fi

# Spotlight launcher (ALT+SPACE / SUPER+\). It lives in a multi-plugin repo
# whose install.sh copies one plugin out, so it is not a git checkout.
if ! skipped mihai.spotlight; then
  step "Spotlight"
  update_flag=()
  [ -e "$PLUGINS_DIR/mihai.spotlight" ] && update_flag=(--update)
  tmp=$(mktemp -d)
  if git clone --quiet --depth 1 https://github.com/nightdevil00/Plugins.git "$tmp/Plugins" &&
    "$tmp/Plugins/install.sh" "${update_flag[@]}" mihai.spotlight; then
    :
  elif ((${#update_flag[@]})); then
    warn "update of mihai.spotlight failed; keeping the installed version"
  else
    warn "could not install mihai.spotlight"
    FAILED=1
  fi
  rm -rf "$tmp"
  [ -e "$PLUGINS_DIR/mihai.spotlight" ] && { omarchy plugin enable mihai.spotlight >/dev/null 2>&1 || true; }
fi

# Altscape: ALT+TAB switcher with previews (SUPER+ALT+A for its settings). Its
# own `altscape-binds sync` writes the ALT+TAB block at the end of hyprland.lua.
if ! skipped io.github.qempexe.altscape; then
  step "Altscape"
  seed "$CONFIG/plugins/seeds/altscape.json" "$HOME/.local/state/omarchy-altscape/settings.json"
  if git_plugin io.github.qempexe.altscape https://github.com/qempexe/omarchy-altscape.git; then
    binds="$PLUGINS_DIR/io.github.qempexe.altscape/bin/altscape-binds"
    [ -x "$binds" ] && { "$binds" sync alt >/dev/null || warn "altscape-binds sync failed"; }
  fi
fi

shell_rescan
in_session && hyprctl reload >/dev/null
exit "$FAILED"
