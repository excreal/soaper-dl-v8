#!/usr/bin/env bash
set -e

# Define required Go version
GO_VERSION="1.24.1"
GO_TAR="go${GO_VERSION}.linux-amd64.tar.gz"
GO_INSTALL_PATH="/usr/local/go"

# Set PATH
echo "Setting up PATH..."
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
echo 'export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/go/bin"' >> ~/.bashrc
source ~/.bashrc
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/go/bin:/usr/local/go/bin"

# Check existing Go version
if command -v go &>/dev/null; then
    INSTALLED_GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    if [[ "$INSTALLED_GO_VERSION" == "$GO_VERSION" ]]; then
        echo "Go $GO_VERSION is already installed. Skipping reinstallation."
    else
        echo "Removing existing Go installation (Version: $INSTALLED_GO_VERSION)..."
        sudo rm -rf "$GO_INSTALL_PATH"
    fi
else
    echo "Go is not installed. Proceeding with installation..."
fi

# Install Go if not installed
if ! command -v go &>/dev/null; then
    echo "Installing Go $GO_VERSION..."
    wget "https://dl.google.com/go/${GO_TAR}"
    sudo tar -C /usr/local -xzf "$GO_TAR"
    rm "$GO_TAR"
fi

# Ensure Go is in PATH
export PATH=$PATH:/usr/local/go/bin
source ~/.bashrc

# Verify Go installation
if ! command -v go &>/dev/null; then
    echo "Error: Go command not found after installation."
    exit 1
fi

# Install required packages
if command -v apt &>/dev/null; then
    echo "Using apt for installation..."
    sudo apt update
    sudo apt install -y curl jq fzf ffmpeg aria2
else
    echo "No supported package manager found (apt)."
    echo "Please install curl, jq, fzf, ffmpeg, and aria2 manually."
    exit 1
fi

export PATH=$PATH:/usr/local/go/bin
source ~/.bashrc

# Install pup using Go
echo "Installing pup using Go..."
go install github.com/ericchiang/pup@latest

# Ensure Go bin directory is in PATH
GOBIN="${GOPATH:-$HOME/go}/bin"
if ! echo "$PATH" | grep -q "$GOBIN"; then
    echo "Warning: $GOBIN is not in your PATH."
    echo "You can add it by running:"
    echo "export PATH=\$PATH:$GOBIN"
fi

# Install yt-dlp
echo "Downloading yt-dlp from the latest release..."
YT_DLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"
curl -L -o yt-dlp "$YT_DLP_URL"

# Rename, make executable, and move yt-dlp to /usr/bin
echo "Making yt-dlp executable and moving it to /usr/bin..."
chmod +x yt-dlp
sudo mv yt-dlp /usr/bin/yt-dlp

echo "yt-dlp has been installed successfully."
echo "All dependencies have been installed successfully."
