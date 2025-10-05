#!/usr/bin/env zsh
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

# Install kubie
if ! command -v kubie &> /dev/null; then
  ARCH=$(get_architecture)
  curl -LO https://github.com/sbstp/kubie/releases/latest/download/kubie-linux-${ARCH}
  mkdir -p "$HOME/.local/bin"
  sudo mv kubie-linux-${ARCH} "$HOME/.local/bin/kubie"
  sudo chmod +x "$HOME/.local/bin/kubie"
fi

# Install kubectl
if ! command -v kubectl &> /dev/null; then
  ARCH=$(get_architecture)
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
  chmod +x kubectl
  sudo mv kubectl ~/.local/bin/
fi

# Install k9s
if ! command -v k9s &> /dev/null; then
  ARCH=$(get_architecture)
  # Note: k9s uses different architecture naming for .deb files
  case "$ARCH" in
    arm64) DEB_ARCH="arm64" ;;
    *) DEB_ARCH="amd64" ;;
  esac
  wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_${DEB_ARCH}.deb
  sudo apt install -y ./k9s_linux_${DEB_ARCH}.deb
  rm k9s_linux_${DEB_ARCH}.deb
fi

# Get username from environment or default to babaji
USERNAME=${USERNAME:-"babaji"}
USER_HOME="/home/${USERNAME}"

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
            chown ${USERNAME}:${USERNAME} "$fragment_file_user" 2>/dev/null || chown ${USERNAME}:users "$fragment_file_user" 2>/dev/null || true
        fi
    elif [ -d "$USER_HOME" ]; then
        # Create the directory if it doesn't exist
        mkdir -p "$USER_HOME/.ohmyzsh_source_load_scripts"
        echo "$fragment_content" > "$fragment_file_user"
        if [ "$USER" != "$USERNAME" ]; then
            chown -R ${USERNAME}:${USERNAME} "$USER_HOME/.ohmyzsh_source_load_scripts" 2>/dev/null || chown -R ${USERNAME}:users "$USER_HOME/.ohmyzsh_source_load_scripts" 2>/dev/null || true
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
