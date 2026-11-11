#!/bin/bash
# Apps: packages, Omarchy installers, web apps and curl-installed apps (manifest/)
source "$(dirname "$0")/../lib/common.sh"

step "Packages"
mapfile -t packages < <(manifest packages.txt | awk '{print $1}')
pkg "${packages[@]}"

step "Omarchy installers"
while read -r cmd args; do
  # shellcheck disable=SC2086 # args is a word list on purpose
  omarchy_install "$cmd" $args || warn "omarchy install $args failed"
done < <(manifest omarchy.txt)

step "Web apps"
APPS_DIR="$HOME/.local/share/applications"
while IFS='|' read -r name url icon; do
  name=$(xargs <<<"$name") url=$(xargs <<<"$url") icon=$(xargs <<<"$icon")
  [ -f "$APPS_DIR/$name.desktop" ] && continue
  note "adding $name ($url)"
  omarchy-webapp-install "$name" "$url" "${icon:+$ASSETS/icons/$icon}" ||
    warn "could not create web app '$name'"
done < <(manifest webapps.txt)

step "Script-installed apps"
while read -r cmd url args; do
  command -v "$cmd" &>/dev/null || [ -x "$HOME/.local/bin/$cmd" ] && continue
  note "installing $cmd ($url)"
  # shellcheck disable=SC2086
  curl -fsSL "$url" | sh -s -- $args || warn "could not install $cmd"
done < <(manifest script-apps.txt)

# Gutenberg's installer drops only the binary, so give it a launcher entry.
# StartupWMClass matches the application_id it sets on its window.
if [ -x "$HOME/.local/bin/gutenberg" ] && [ ! -f "$APPS_DIR/gutenberg.desktop" ]; then
  install -Dm644 "$ASSETS/icons/gutenberg.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/gutenberg.svg"
  cat >"$APPS_DIR/gutenberg.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Gutenberg
GenericName=News Reader
Comment=Read feeds and articles
Exec=$HOME/.local/bin/gutenberg
Icon=gutenberg
Terminal=false
StartupWMClass=gutenberg
Categories=Network;News;
Keywords=rss;atom;feed;news;reader;
EOF
  note "added the Gutenberg launcher entry"
fi

# Cronkite (cronkite.cc) is the office suite: Slate (documents), Brick
# (spreadsheets) and Frame (slides) become the default for every file type
# their launchers declare, except text/plain, which stays with the text editor.
# LibreOffice (an Omarchy base package) keeps the formats Cronkite can't open:
# OpenDocument, legacy .doc/.xls/.ppt, and .rtf.
step "Office suite: Cronkite"
for app in dev.cronkite.Slate dev.cronkite.Brick dev.cronkite.Frame; do
  desktop="$APPS_DIR/$app.desktop"
  [ -f "$desktop" ] || { warn "$app is not installed"; continue; }
  for mime in $(sed -n 's/^MimeType=//p' "$desktop" | tr ';' ' '); do
    [ "$mime" = text/plain ] && continue
    [ "$(xdg-mime query default "$mime")" = "$app.desktop" ] || xdg-mime default "$app.desktop" "$mime"
  done
done
# Legacy .xls would otherwise fall to whatever else claims it (ChatGPT, here).
[ "$(xdg-mime query default application/vnd.ms-excel)" = libreoffice-calc.desktop ] ||
  xdg-mime default libreoffice-calc.desktop application/vnd.ms-excel

# Omarchy iCloud Photos: recent iCloud photos in a launcher, plus a sync timer.
# Cloned under ~/Documents (which Syncthing may already have delivered); its
# install.sh symlinks into the checkout. The Apple sign-in is per machine.
step "Omarchy iCloud Photos"
ICLOUD_SRC="$HOME/Documents/github.com/jankeesvw/omarchy-icloud-photos"
[ -d "$ICLOUD_SRC" ] ||
  git clone --quiet https://github.com/jankeesvw/omarchy-icloud-photos.git "$ICLOUD_SRC" ||
  warn "could not clone omarchy-icloud-photos"
if [ -x "$ICLOUD_SRC/install.sh" ] && [ ! -e "$HOME/.local/bin/omarchy-icloud-photos" ]; then
  "$ICLOUD_SRC/install.sh" || warn "omarchy-icloud-photos install failed"
fi
