#!/bin/bash
set -e

# Logging mechanism for debugging
LOG_FILE="/tmp/k8s-utilities-install.log"
log_debug() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $*" >> "$LOG_FILE"
}

# Initialize logging
log_debug "=== K8S-UTILITIES INSTALL STARTED ==="
log_debug "Script path: $0"
log_debug "PWD: $(pwd)"
log_debug "Environment: USER=$USER HOME=$HOME"

# Set non-interactive environment
export DEBIAN_FRONTEND=noninteractive

# Audit fix 2026-05-15 + 2026-05-18: resolve runtime user/home/group dynamically.
# Reject _REMOTE_USER=root (which devcontainer features can set at build time and
# would defeat the fallback chain — landing kubie in /root/.local/bin instead of
# $USER_HOME/.local/bin, invisible to the runtime user).
USERNAME="${USERNAME:-${_REMOTE_USER:-}}"
if [ -z "$USERNAME" ] || [ "$USERNAME" = "root" ]; then
    if getent passwd vishkrm >/dev/null 2>&1; then
        USERNAME=vishkrm
    else
        USERNAME=$(getent passwd | awk -F: '$3>=1000 && $1!="nobody" {print $1; exit}')
    fi
fi
USER_HOME="$(getent passwd "$USERNAME" 2>/dev/null | cut -d: -f6)"
[ -z "$USER_HOME" ] && USER_HOME="/home/${USERNAME}"
USER_GROUP="$(id -gn "$USERNAME" 2>/dev/null || echo users)"
USER_BIN="${USER_HOME}/.local/bin"

# Ensure target dir exists with correct ownership BEFORE root-owned sudo mv
mkdir -p "$USER_BIN"
chown "${USERNAME}:${USER_GROUP}" "$USER_HOME/.local" "$USER_BIN" 2>/dev/null || true

# Function to get system architecture
get_architecture() {
    local arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
    esac
}

# Install kubie (to runtime user's $HOME/.local/bin, not /root/.local/bin)
if [ ! -x "$USER_BIN/kubie" ]; then
  ARCH=$(get_architecture)
  echo "Downloading kubie for linux-${ARCH}..."
  curl -fLo /tmp/kubie "https://github.com/sbstp/kubie/releases/latest/download/kubie-linux-${ARCH}"
  install -m 0755 -o "$USERNAME" -g "$USER_GROUP" /tmp/kubie "$USER_BIN/kubie"
  rm -f /tmp/kubie
  echo "kubie installed at $USER_BIN/kubie"
fi

# Install kubectl (to /usr/local/bin — system-wide, always on PATH)
if ! command -v kubectl &> /dev/null; then
  ARCH=$(get_architecture)
  KVER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  echo "Downloading kubectl ${KVER} for linux-${ARCH}..."
  curl -fLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl"
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
  echo "kubectl installed at /usr/local/bin/kubectl"
fi

# Install k9s
if ! command -v k9s &> /dev/null; then
  ARCH=$(get_architecture)
  case "$ARCH" in
    arm64) DEB_ARCH="arm64" ;;
    *) DEB_ARCH="amd64" ;;
  esac
  wget -q "https://github.com/derailed/k9s/releases/latest/download/k9s_linux_${DEB_ARCH}.deb" -O /tmp/k9s.deb
  sudo apt install -y /tmp/k9s.deb
  rm -f /tmp/k9s.deb
fi

# 🧩 Create Self-Healing Environment Fragment
create_environment_fragment() {
    local feature_name="k8s-tools"
    local fragment_file_skel="/etc/skel/.ohmyzsh_source_load_scripts/.${feature_name}.zshrc"
    local fragment_file_user="$USER_HOME/.ohmyzsh_source_load_scripts/.${feature_name}.zshrc"
    
    # Create fragment content with self-healing detection
    local fragment_content='# ☸️ Kubernetes Tools Environment Fragment
# Self-healing detection and environment setup

# Check if k8s tools are available
k8s_tools_available=false

# Ensure local bin is in PATH
if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# Check for kubectl and setup completion
if command -v kubectl >/dev/null 2>&1; then
    k8s_tools_available=true
    alias k=kubectl
    
    # Setup kubectl completion for zsh
    if [ -n "$ZSH_VERSION" ]; then
        autoload -U compinit && compinit
        source <(kubectl completion zsh)
        complete -o default -F __start_kubectl k
    fi
fi

# Check for k9s
if command -v k9s >/dev/null 2>&1; then
    k8s_tools_available=true
fi

# Check for kubie
if command -v kubie >/dev/null 2>&1; then
    k8s_tools_available=true
fi

# If no k8s tools are available, cleanup this fragment
if [ "$k8s_tools_available" = false ]; then
    echo "Kubernetes tools removed, cleaning up environment"
    rm -f "$HOME/.ohmyzsh_source_load_scripts/.k8s-tools.zshrc"
fi'

    # Create fragment for /etc/skel
    if [ -d "/etc/skel/.ohmyzsh_source_load_scripts" ]; then
        echo "$fragment_content" > "$fragment_file_skel"
    fi

    # Create fragment for existing user
    if [ -d "$USER_HOME/.ohmyzsh_source_load_scripts" ]; then
        echo "$fragment_content" > "$fragment_file_user"
        if [ "$USER" != "$USERNAME" ]; then
            chown "${USERNAME}:${USER_GROUP}" "$fragment_file_user" 2>/dev/null || true
        fi
    elif [ -d "$USER_HOME" ]; then
        # Create the directory if it doesn't exist
        mkdir -p "$USER_HOME/.ohmyzsh_source_load_scripts"
        echo "$fragment_content" > "$fragment_file_user"
        if [ "$USER" != "$USERNAME" ]; then
            chown -R "${USERNAME}:${USER_GROUP}" "$USER_HOME/.ohmyzsh_source_load_scripts" 2>/dev/null || true
        fi
    fi
    
    echo "Self-healing environment fragment created: .k8s-tools.zshrc"
}

# Call the fragment creation function
create_environment_fragment

# Clean up
sudo apt-get clean

log_debug "=== K8S-UTILITIES INSTALL COMPLETED ==="
# Auto-trigger build Tue Sep 23 20:03:15 BST 2025
