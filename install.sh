#!/usr/bin/env bash
# Install the browser-switcher CLI and Omarchy shell plugin.
#
# Every step is opt-in past the basics, because the interesting ones change
# system-wide behaviour: --set-default takes over your link handling and
# --hyprland edits hyprland.lua. Run it bare first and see what you get.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="sven.browser-switcher"
BIN_DIR="${HOME}/.local/bin"
PLUGIN_DIR="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"

ENABLE=0
SET_DEFAULT=0
HYPRLAND=0
ADOPT=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

  --enable        add the widget to the Omarchy bar
  --adopt         register existing hand-made profile launchers (non-destructive)
  --hyprland      add the generated window-border rules to hyprland.lua
  --set-default   make browser-switcher the handler for opened links
  --all           all of the above
  -h, --help      show this help

With no options it installs the CLI and the plugin files only, and changes
nothing about how your system currently opens links.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --enable) ENABLE=1 ;;
    --adopt) ADOPT=1 ;;
    --hyprland) HYPRLAND=1 ;;
    --set-default) SET_DEFAULT=1 ;;
    --all) ENABLE=1; ADOPT=1; HYPRLAND=1; SET_DEFAULT=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

step() { printf '\n\033[1m==>\033[0m %s\n' "$1"; }

# ---------------------------------------------------------------- dependencies
missing=()
for dep in python3 magick; do
  command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing required commands: ${missing[*]}" >&2
  echo "Install them with: omarchy pkg add imagemagick" >&2
  exit 1
fi

# ---------------------------------------------------------------------- CLI
step "Installing the browser-switcher CLI into ${BIN_DIR}"
mkdir -p "${BIN_DIR}"
ln -sfn "${REPO}/bin/browser-switcher" "${BIN_DIR}/browser-switcher"
echo "    ${BIN_DIR}/browser-switcher -> ${REPO}/bin/browser-switcher"

case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *) echo "    note: ${BIN_DIR} is not on your PATH" ;;
esac

# ------------------------------------------------------------------- plugin
# Symlinked rather than copied so editing the checkout hot-reloads the shell.
step "Linking the shell plugin into ~/.config/omarchy/plugins"
mkdir -p "$(dirname "${PLUGIN_DIR}")"
if [[ -e "${PLUGIN_DIR}" && ! -L "${PLUGIN_DIR}" ]]; then
  echo "    ${PLUGIN_DIR} exists and is not a symlink — leaving it alone" >&2
  exit 1
fi
ln -sfn "${REPO}" "${PLUGIN_DIR}"
echo "    ${PLUGIN_DIR} -> ${REPO}"

# --------------------------------------------------------------------- setup
step "Installing the link router"
INSTALL_ARGS=()
[[ ${SET_DEFAULT} -eq 1 ]] && INSTALL_ARGS+=(--set-default)
[[ ${HYPRLAND} -eq 1 ]] && INSTALL_ARGS+=(--hyprland)
"${BIN_DIR}/browser-switcher" install "${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}"

if [[ ${ADOPT} -eq 1 ]]; then
  step "Adopting existing profile launchers"
  "${BIN_DIR}/browser-switcher" adopt
fi

# ---------------------------------------------------------------------- shell
step "Telling the Omarchy shell to rescan its plugins"
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins || echo "    (shell not running — it will pick the plugin up on next start)"
else
  echo "    omarchy-shell not found; skipping rescan"
fi

if [[ ${ENABLE} -eq 1 ]]; then
  step "Adding the widget to the bar"
  omarchy plugin enable "${PLUGIN_ID}"
fi

step "Done"
"${BIN_DIR}/browser-switcher" doctor || true

cat <<NEXT

Next steps:
  browser-switcher list                     what you have now
  browser-switcher adopt                    pick up hand-made launchers as-is
  browser-switcher add --name "Client C"    create a fresh isolated client
  omarchy plugin enable ${PLUGIN_ID}    put the widget in the bar

To back everything out:
  omarchy plugin disable ${PLUGIN_ID}
  browser-switcher uninstall
  rm "${PLUGIN_DIR}" "${BIN_DIR}/browser-switcher"
NEXT
