#!/bin/bash
# Provision this machine after a clean Omarchy install. Same as ./setup
# (kept so the familiar name still works); arguments are passed through.
exec "$(dirname "$(readlink -f "$0")")/setup" "$@"
