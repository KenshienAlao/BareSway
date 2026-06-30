#!/bin/bash

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✘]${NC} $*"; }
step()  { echo -e "\n${BOLD}── $* ──${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── System Update ────────────────────────────────────────────────────
step "System Update"

read -rp "Update system first? [y/N]: " update
if [[ "${update,,}" == "y" ]]; then
    info "Running pacman -Syu..."
    sudo pacman -Syu --noconfirm
else
    warn "Skipping system update."
fi

# ── Install Packages ────────────────────────────────────────────────
step "Installing Packages"

PACKAGES=(
    git
    rsync
    sway
    wofi
    foot
    xdg-utils
    dbus
    xdg-desktop-portal
    xdg-desktop-portal-wlr
    at-spi2-core
    firefox
    thunar 
    grim slurp
    waybar
    pipewire pipewire-pulse wireplumber pavucontrol
)

# Only install packages that aren't already present
TO_INSTALL=()
for pkg in "${PACKAGES[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        TO_INSTALL+=("$pkg")
    fi
done

if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    info "Installing: ${TO_INSTALL[*]}"
    sudo pacman -S --needed --noconfirm "${TO_INSTALL[@]}"
else
    info "All packages already installed."
fi

info "Enabling Pipewire services..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber

# ── AUR Helper ──────────────────────────────────────────────────────
step "AUR Helper"

install_aur_helper() {
    local name="$1"
    local url="https://aur.archlinux.org/${name}.git"

    if command -v "$name" &>/dev/null; then
        info "${name} is already installed."
        return
    fi

    info "Building ${name} from AUR..."
    local tmpdir
    tmpdir="$(mktemp -d)"
    git clone "$url" "$tmpdir/$name"
    (cd "$tmpdir/$name" && makepkg -si)
    rm -rf "$tmpdir"
    info "${name} installed successfully."
}

echo "Choose an AUR helper:"
echo "  1) yay  (default)"
echo "  2) paru"
read -rp "Enter choice [1/2]: " choice

case "${choice:-1}" in
    2) 
        install_aur_helper paru || exit 1
        AUR_HELPER="paru"
        ;;
    *) 
        install_aur_helper yay || exit 1
        AUR_HELPER="yay"
        ;;
esac

if ! command -v "$AUR_HELPER" &>/dev/null; then
    error "AUR helper not found!"
    exit 1
fi

echo "Do you want to install VSCode?"
read -rp "Enter choice [Y/n]: " choice

if [[ "${choice,,}" == "n" ]]; then
    info "Skipping VSCode installation"
else
    info "Installing VSCode via $AUR_HELPER..."
    $AUR_HELPER -S --needed --noconfirm \
        visual-studio-code-bin
fi

echo "Do you want to install Discord?"
read -rp "Enter choice [Y/n]: " choice

if [[ "${choice,,}" == "n" ]]; then
    info "Skipping Discord installation"
else
    info "Installing Discord via $AUR_HELPER..."
    $AUR_HELPER -S --needed --noconfirm \
        vesktop-bin
fi

# ── Sway Config ─────────────────────────────────────────────────────
step "Sway Configuration"

SWAY_SRC="${SCRIPT_DIR}/sway"
SWAY_DST="${HOME}/.config/sway"

if [[ ! -d "$SWAY_SRC" ]]; then
    error "Source config not found at ${SWAY_SRC}"
    exit 1
fi

mkdir -p "$SWAY_DST"
rsync -a --delete \
    --exclude ".bash_profile" \
    --exclude "waybar" \
    --exclude "foot" \
    --exclude "wofi" \
    "${SWAY_SRC}/." "$SWAY_DST/"
info "Sway config deployed to ${SWAY_DST}"

# ── Waybar Config ───────────────────────────────────────────────────
step "Waybar Configuration"

WAYBAR_SRC="${SWAY_SRC}/waybar"
WAYBAR_DST="${HOME}/.config/waybar"

if [[ ! -d "$WAYBAR_SRC" ]] || [[ -z "$(ls -A "$WAYBAR_SRC")" ]]; then
    warn "Waybar config missing or empty, skipping installation"
else
    mkdir -p "$WAYBAR_DST"
    rsync -a --delete "${WAYBAR_SRC}/." "$WAYBAR_DST/"
    info "Waybar config deployed to ${WAYBAR_DST}"
fi

# ── Foot Config ───────────────────────────────────────────────────
step "Foot Configuration"

FOOT_SRC="${SWAY_SRC}/foot"
FOOT_DST="${HOME}/.config/foot"

if [[ ! -d "$FOOT_SRC" ]] || [[ -z "$(ls -A "$FOOT_SRC")" ]]; then
    warn "Foot config missing or empty, skipping installation"
else
    mkdir -p "$FOOT_DST"
    rsync -a --delete "${FOOT_SRC}/." "$FOOT_DST/"
    info "Foot config deployed to ${FOOT_DST}"
fi

# ── Wofi Config ───────────────────────────────────────────────────
step "Wofi Configuration"

WOFI_SRC="${SWAY_SRC}/wofi"
WOFI_DST="${HOME}/.config/wofi"

if [[ ! -d "$WOFI_SRC" ]] || [[ -z "$(ls -A "$WOFI_SRC")" ]]; then
    warn "Wofi config missing or empty, skipping installation"
else
    mkdir -p "$WOFI_DST"
    rsync -a --delete "${WOFI_SRC}/." "$WOFI_DST/"
    info "Wofi config deployed to ${WOFI_DST}"
fi

# ── Shell Profile ───────────────────────────────────────────────────
step "Shell Profile"

BASH_PROFILE_SRC="${SWAY_SRC}/.bash_profile"
BASH_PROFILE_DST="${HOME}/.bash_profile"

if [[ -f "$BASH_PROFILE_SRC" ]]; then
    if [[ -f "$BASH_PROFILE_DST" ]]; then
        # Remove old block if it exists (avoids duplication on updates)
        sed -i '/# === MINIMAL SWAY SETUP ===/,/# === END MINIMAL SWAY SETUP ===/d' "$BASH_PROFILE_DST"
        
        # Append new block with markers
        echo "" >> "$BASH_PROFILE_DST"
        echo "# === MINIMAL SWAY SETUP ===" >> "$BASH_PROFILE_DST"
        cat "$BASH_PROFILE_SRC" >> "$BASH_PROFILE_DST"
        echo "# === END MINIMAL SWAY SETUP ===" >> "$BASH_PROFILE_DST"
        
        info "Injected Sway startup logic to ${BASH_PROFILE_DST}"
    else
        echo "# === MINIMAL SWAY SETUP ===" > "$BASH_PROFILE_DST"
        cat "$BASH_PROFILE_SRC" >> "$BASH_PROFILE_DST"
        echo "# === END MINIMAL SWAY SETUP ===" >> "$BASH_PROFILE_DST"
        info "Created .bash_profile with Sway startup logic"
    fi
else
    warn "No .bash_profile found in ${SWAY_SRC}, skipping."
fi

# ── Done ────────────────────────────────────────────────────────────
echo ""
info "Setup complete!"
echo ""
echo "What would you like to do now?"
echo "  1) Log out (terminates session and drops to TTY/Display Manager)"
echo "  2) Reboot"
echo "  3) Stay in current environment (default)"
read -rp "Enter choice [1/2/3]: " exit_choice

case "${exit_choice}" in
    1)
        info "Logging out..."
        sleep 1
        loginctl terminate-user "$USER"
        ;;
    2)
        info "Rebooting..."
        sleep 1
        systemctl reboot
        ;;
    *)
        info "Staying in current environment. Log out manually later to start Sway."
        ;;
esac
