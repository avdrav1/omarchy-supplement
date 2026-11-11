# omarchy-supplement

Everything that turns a fresh [Omarchy](https://omarchy.org/) install into one
of my machines: apps, shell, dotfiles, Hyprland overrides, theme, the Shibumi
bar and its widgets, and shell plugins. Anything Omarchy already installs or
configures is left to Omarchy.

## Use

```sh
git clone https://github.com/avdrav1/omarchy-supplement ~/omarchy-supplement
~/omarchy-supplement/setup            # everything, then the manual steps
~/omarchy-supplement/setup --list     # what the modules are
~/omarchy-supplement/setup hyprland   # just one (or several) modules
```

`setup` first fast-forwards this repo from GitHub (so a machine always applies
the current config; `SUPPLEMENT_NO_PULL=1` skips that), asks for sudo once, and
runs each module in its own process. A failing module doesn't stop the others;
they're listed at the end. Every module is safe to re-run.

## Layout

| Path | What it is |
|---|---|
| `setup` | Entry point |
| `lib/common.sh` | Helpers every module uses (`pkg`, `omarchy_install`, `seed`, `put`, services) |
| `modules/NN-name.sh` | One area each, run in `NN` order |
| `manifest/` | Plain lists of what gets installed: packages, Omarchy installers, web apps, curl-installed apps, bar widgets |
| `config/` | Files placed on the machine: `hypr/` (Lua overrides + per-host scale), `themes/`, `shibumi/`, `blueferry/`, `plugins/` (patches + seeded settings), `pacman/` |
| `assets/icons/` | Icons for web apps and launchers |
| `tools/` | Helpers run by hand |
| `docs/manual-steps.txt` | What still needs a human after `setup` |

Dotfiles (zsh, nvim, ghostty, aerc, VS Code, Vesktop, herdr, widget settings)
live in the separate [`avdrav1/dotfiles`](https://github.com/avdrav1/dotfiles)
repo; `modules/30-dotfiles.sh` clones and stows it.

## Common changes

- **Add an app:** one line in `manifest/packages.txt` (or `omarchy.txt`,
  `webapps.txt`, `script-apps.txt`), then `./setup packages`.
- **Add a bar widget:** one line in `manifest/bar-widgets.txt`, then
  `./setup bar-widgets`.
- **Change a keybinding or window rule:** edit `config/hypr/*.lua`; Hyprland
  reloads on save. Check with `hyprctl configerrors`.
- **Set a machine's display scale:** edit `config/hypr/hosts/<hostname>.lua`,
  run `./setup hyprland`, commit. (Scale goes through a generated
  `~/.config/hypr/monitors.lua` because Omarchy re-applies it every 2s from
  that file -- see `modules/40-hyprland.sh`.)
- **Keep Shibumi settings:** after changing them in its control center, run
  `tools/save-shibumi-settings.sh` and commit `config/shibumi/settings.json`.
- **Change the theme:** edit it in Aether, then copy
  `~/.config/omarchy/themes/rebirth` over `config/themes/rebirth` and commit.

Commit and push: other machines only see what's on GitHub.
