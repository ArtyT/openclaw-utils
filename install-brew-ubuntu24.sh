#!/usr/bin/env bash
set -euo pipefail

# ---- Config (override via env) ----
BREW_USER="${BREW_USER:-brew}"
BREW_USER_PASSWORD="${BREW_USER_PASSWORD:-}"   # optional; if empty, user has no password set unless you set it later
BREW_INSTALL_DIR="${BREW_INSTALL_DIR:-/home/linuxbrew/.linuxbrew}"
ALLOW_PASSWORDLESS_SUDO="${ALLOW_PASSWORDLESS_SUDO:-0}"  # set to 1 if you want NOPASSWD sudo

# ---- Helpers ----
log() { echo "[brew-setup] $*"; }
die() { echo "[brew-setup] ERROR: $*" >&2; exit 1; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Run as root (or: sudo bash $0)"
  fi
}

# ---- 1) Create non-root user ----
create_user() {
  if id -u "$BREW_USER" >/dev/null 2>&1; then
    log "User '$BREW_USER' already exists"
  else
    log "Creating user '$BREW_USER'..."
    useradd -m -s /bin/bash "$BREW_USER"
  fi

  log "Ensuring '$BREW_USER' is in sudo group..."
  usermod -aG sudo "$BREW_USER"

  if [[ "$ALLOW_PASSWORDLESS_SUDO" == "1" ]]; then
    log "Enabling passwordless sudo for '$BREW_USER'..."
    cat >/etc/sudoers.d/90-"$BREW_USER"-nopasswd <<EOF
$BREW_USER ALL=(ALL) NOPASSWD:ALL
EOF
    chmod 0440 /etc/sudoers.d/90-"$BREW_USER"-nopasswd
  fi

  if [[ -n "$BREW_USER_PASSWORD" ]]; then
    log "Setting password for '$BREW_USER'..."
    echo "$BREW_USER:$BREW_USER_PASSWORD" | chpasswd
  else
    log "No BREW_USER_PASSWORD provided; not changing password."
  fi
}

# ---- 2) Install dependencies for Homebrew ----
install_deps() {
  log "Installing packages needed for Homebrew..."
  apt-get update -y
  apt-get install -y --no-install-recommends \
    build-essential \
    procps \
    curl \
    file \
    git \
    ca-certificates \
    locales

  # Ensure locale exists (Homebrew can be picky in some environments)
  if ! locale -a | grep -qiE '^en_US\.utf8$'; then
    log "Generating en_US.UTF-8 locale..."
    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8
  fi
}

# ---- 3) Install Homebrew as the non-root user ----
install_brew() {
  log "Preparing install dir: $BREW_INSTALL_DIR"
  mkdir -p "$BREW_INSTALL_DIR"
  chown -R "$BREW_USER":"$BREW_USER" "$(dirname "$BREW_INSTALL_DIR")"

  log "Installing Homebrew as user '$BREW_USER'..."
  # Use the official installer. NONINTERACTIVE avoids prompts.
  su - "$BREW_USER" -c "NONINTERACTIVE=1 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
}

# ---- 4) System-wide PATH setup ----
setup_path() {
  log "Setting up /etc/profile.d/homebrew.sh for system-wide brew PATH..."
  cat >/etc/profile.d/homebrew.sh <<'EOF'
# Homebrew on Linux
if [ -d /home/linuxbrew/.linuxbrew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
EOF
  chmod 0644 /etc/profile.d/homebrew.sh

  # Also ensure the brew user gets it in their shell immediately
  log "Ensuring '$BREW_USER' sources Homebrew env in ~/.bashrc..."
  su - "$BREW_USER" -c "grep -q 'brew shellenv' ~/.bashrc 2>/dev/null || printf '\n# Homebrew\nif [ -d /home/linuxbrew/.linuxbrew ]; then\n  eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\"\nfi\n' >> ~/.bashrc"
}

# ---- 5) Validate ----
validate() {
  log "Validating brew install..."
  su - "$BREW_USER" -c "source /etc/profile.d/homebrew.sh && brew --version"
  log "Homebrew is installed and working for user '$BREW_USER'."
  log "Open a new shell (or: source /etc/profile.d/homebrew.sh) to use brew."
}

main() {
  require_root
  create_user
  install_deps
  install_brew
  setup_path
  validate
}

main "$@"
