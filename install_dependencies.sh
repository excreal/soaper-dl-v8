#!/usr/bin/env bash
set -e

# Detect package manager and install dependencies
if command -v apt >/dev/null 2>&1; then
    echo "Using apt for installation..."
    sudo apt update
    sudo apt install -y curl jq fzf ffmpeg aria2 golang
#elif command -v pacman >/dev/null 2>&1; then
#    echo "Using pacman for installation (Arch Linux)..."
#    sudo pacman -Sy --needed curl jq fzf ffmpeg aria2-git
elif command -v brew >/dev/null 2>&1; then
    echo "Using Homebrew for installation..."
    brew update
    brew install curl jq fzf ffmpeg aria2
else
    echo "No supported package manager found (apt-get, pacman, or brew)."
    echo "Please install curl, jq, fzf, ffmpeg, and aria2 manually."
    exit 1
fi

# Check if Go is installed for pup installation
if ! command -v go >/dev/null 2>&1; then
    echo "Go is not installed. Please install Go from https://golang.org/dl/ and re-run this script."
    exit 1
fi

echo "Installing pup using Go..."
go install github.com/ericchiang/pup@latest

# Ensure the Go bin directory is in your PATH
GOBIN="${GOPATH:-$HOME/go}/bin"
if ! echo "$PATH" | grep -q "$GOBIN"; then
    echo "Warning: $GOBIN is not in your PATH."
    echo "You can add it by running:"
    echo "export PATH=\$PATH:$GOBIN"
fi

echo "All dependencies have been installed successfully."
