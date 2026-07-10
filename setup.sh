#!/bin/bash

set -euo pipefail

# ── Colors & Logging ─────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✘]${NC} $*"; }
step()  { echo -e "\n${BOLD}── $* ──${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWAY_SRC="${SCRIPT_DIR}/sway"

# ── Helpers ──────────────────────────────────────────────────────────

# deploy_config <name> <src_dir> <dst_dir>
#   Checks if src exists and is non-empty, then rsyncs to dst.
deploy_config() {
    local name="$1" src="$2" dst="$3"

    if [[ ! -d "$src" ]] || [[ -z "$(ls -A "$src" 2>/dev/null)" ]]; then
        warn "${name} config missing or empty, skipping"
        return 1
    fi

    mkdir -p "$dst"
    rsync -a --delete "${src}/." "$dst/"
    info "${name} config deployed to ${dst}"
}

install_aur_helper() {
    local name="$1"

    if command -v "$name" &>/dev/null; then
        info "${name} is already installed."
        return
    fi

    info "Building ${name} from AUR..."
    local tmpdir
    tmpdir="$(mktemp -d)"
    git clone "https://aur.archlinux.org/${name}.git" "$tmpdir/$name"
    (cd "$tmpdir/$name" && makepkg -si)
    rm -rf "$tmpdir"
    info "${name} installed successfully."
}

# ══════════════════════════════════════════════════════════════════════
#  1. SYSTEM UPDATE
# ══════════════════════════════════════════════════════════════════════
step "System Update"

read -rp "Update system first? [y/N]: " update
if [[ "${update,,}" == "y" ]]; then
    info "Running pacman -Syu..."
    sudo pacman -Syu --noconfirm
else
    warn "Skipping system update."
fi

# ══════════════════════════════════════════════════════════════════════
#  2. PACKAGES (pacman)
# ══════════════════════════════════════════════════════════════════════
step "Installing Packages"

PACKAGES=(
    # Core / WM
    git rsync sway

    # Launcher / Terminal
    wofi foot

    # Portal & Accessibility
    qt5-wayland qt6-wayland xdg-utils dbus xdg-desktop-portal xdg-desktop-portal-wlr at-spi2-core

    # Apps
    firefox thunar

    # Screenshot
    grim slurp

    # Bar
    waybar

    # Audio
    pipewire pipewire-pulse wireplumber pavucontrol

    # Wallpaper
    awww

    # yad
    yad

    # video viewer 
    mpv
)

TO_INSTALL=()
for pkg in "${PACKAGES[@]}"; do
    pacman -Qi "$pkg" &>/dev/null || TO_INSTALL+=("$pkg")
done

if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    info "Installing: ${TO_INSTALL[*]}"
    sudo pacman -S --needed --noconfirm "${TO_INSTALL[@]}"
else
    info "All packages already installed."
fi

# Enable audio stack
info "Enabling Pipewire services..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber

# awww needs a cache dir
mkdir -p ~/.cache/awww

# ══════════════════════════════════════════════════════════════════════
#  3. AUR HELPER & OPTIONAL PACKAGES
# ══════════════════════════════════════════════════════════════════════
step "AUR Helper"

echo "Choose an AUR helper:"
echo "  1) yay  (default)"
echo "  2) paru"
read -rp "Enter choice [1/2]: " choice

case "${choice:-1}" in
    2) install_aur_helper paru || exit 1; AUR_HELPER="paru" ;;
    *) install_aur_helper yay  || exit 1; AUR_HELPER="yay"  ;;
esac

if ! command -v "$AUR_HELPER" &>/dev/null; then
    error "AUR helper not found!"
    exit 1
fi

# ── Optional AUR packages ───────────────────────────────────────────
declare -A AUR_PACKAGES=(
    ["VSCode"]="visual-studio-code-bin"
    ["Discord (Vesktop)"]="vesktop-bin"
)

for label in "${!AUR_PACKAGES[@]}"; do
    read -rp "Install ${label}? [Y/n]: " ans
    if [[ "${ans,,}" == "n" ]]; then
        info "Skipping ${label}"
    else
        info "Installing ${label} via ${AUR_HELPER}..."
        $AUR_HELPER -S --needed --noconfirm "${AUR_PACKAGES[$label]}"
    fi
done

# ══════════════════════════════════════════════════════════════════════
#  4. DEPLOY CONFIGS
# ══════════════════════════════════════════════════════════════════════

# ── Validate source repo ─────────────────────────────────────────────
if [[ ! -d "$SWAY_SRC" ]]; then
    error "Source config not found at ${SWAY_SRC}"
    exit 1
fi

SWAY_DST="${HOME}/.config/sway"

# ── Sway (core configs, excluding sub-components) ────────────────────
step "Sway Configuration"

mkdir -p "$SWAY_DST"
rsync -a --delete \
    --exclude ".bash_profile" \
    --exclude "waybar" \
    --exclude "foot" \
    --exclude "wofi" \
    --exclude "wallpaper" \
    --exclude "help" \
    "${SWAY_SRC}/." "$SWAY_DST/"
info "Sway config deployed to ${SWAY_DST}"

# ── Sub-components (each goes to its own ~/.config/<app>/) ───────────
step "Deploying Sub-Configs"

deploy_config "Waybar"    "${SWAY_SRC}/waybar"    "${HOME}/.config/waybar"
deploy_config "Foot"      "${SWAY_SRC}/foot"      "${HOME}/.config/foot"
deploy_config "Wofi"      "${SWAY_SRC}/wofi"      "${HOME}/.config/wofi"
deploy_config "Wallpaper" "${SWAY_SRC}/wallpaper"  "${SWAY_DST}/wallpaper"
deploy_config "Help"      "${SWAY_SRC}/help"      "${SWAY_DST}/help"

# ── Scripts ──────────────────────────────────────────────────────────
step "Scripts"

SCRIPTS_DST="${SWAY_DST}/scripts"
mkdir -p "$SCRIPTS_DST"

# Collect all .sh files from the wallpaper source dir
SCRIPT_COUNT=0
while IFS= read -r -d '' script; do
    cp "$script" "${SCRIPTS_DST}/"
    chmod +x "${SCRIPTS_DST}/$(basename "$script")"
    info "$(basename "$script") → ${SCRIPTS_DST}"
    ((SCRIPT_COUNT++))
done < <(find "${SWAY_SRC}/wallpaper" -maxdepth 1 -name '*.sh' -print0 2>/dev/null)

[[ $SCRIPT_COUNT -eq 0 ]] && warn "No scripts found to deploy"

# ══════════════════════════════════════════════════════════════════════
#  5. SHELL PROFILE
# ══════════════════════════════════════════════════════════════════════
step "Shell Profile"

BASH_PROFILE_SRC="${SWAY_SRC}/.bash_profile"
BASH_PROFILE_DST="${HOME}/.bash_profile"
MARKER_START="# === MINIMAL SWAY SETUP ==="
MARKER_END="# === END MINIMAL SWAY SETUP ==="

if [[ -f "$BASH_PROFILE_SRC" ]]; then
    # Strip any existing block to avoid duplication
    if [[ -f "$BASH_PROFILE_DST" ]]; then
        sed -i "/${MARKER_START}/,/${MARKER_END}/d" "$BASH_PROFILE_DST"
    fi

    {
        echo ""
        echo "$MARKER_START"
        cat "$BASH_PROFILE_SRC"
        echo "$MARKER_END"
    } >> "$BASH_PROFILE_DST"

    info "Sway startup logic injected into ${BASH_PROFILE_DST}"
else
    warn "No .bash_profile found in ${SWAY_SRC}, skipping"
fi

# ══════════════════════════════════════════════════════════════════════
#  6. DONE
# ══════════════════════════════════════════════════════════════════════
echo ""
info "Setup complete!"
echo ""
echo "What would you like to do now?"
echo "  1) Log out (drops to TTY / Display Manager)"
echo "  2) Reboot"
echo "  3) Stay here (default)"
read -rp "Enter choice [1/2/3]: " exit_choice

case "${exit_choice}" in
    1) info "Logging out...";  sleep 1; loginctl terminate-user "$USER" ;;
    2) info "Rebooting...";    sleep 1; systemctl reboot ;;
    *) info "Staying in current environment. Log out manually to start Sway." ;;
esac
