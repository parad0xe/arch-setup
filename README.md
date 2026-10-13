# Arch Linux Setup - Hyprland Edition

This repository contains a set of modular scripts designed to automate
the installation and configuration of a complete Arch Linux environment.

## Features

* Modular Architecture: Scripts divided by theme (Core, Hardware, etc.).
* NVIDIA Optimized: Automatic driver installation and DRM configuration
  when an NVIDIA GPU is detected.
* ARM Support: Runs on Arch Linux ARM (aarch64, e.g. Asahi Linux on Apple
  Silicon); see the notes for the differences.
* Dotfiles Management: Deployment via symbolic links to ~/.config.
* Complete Environment: Hyprland, Waybar, ZSH, PipeWire, and Bluetooth.

## Project Structure

* setup.sh: Main orchestrator and global variables.
* bootstrap.sh: Entry script to clone the repo into ~/.dotfiles.
* modules/: Individual installation scripts.
* .config/: Configurations for Hyprland, Waybar, Mako, Ghostty, etc.

## Configuration

Nothing needs to be edited before launching: the setup asks for your
personal settings (SSH key email, Git name and email, timezone) and lets you
choose between config variants (e.g. keybindings, keyboard layout).

Machine-specific SSH settings (hosts, extra keys) go in `~/.ssh/config.d/`,
which is included by the versioned SSH config but never versioned itself.

## Installation

On a fresh Arch Linux installation, run the following command:

```bash
git clone https://github.com/parad0xe/arch-setup.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh
```

### Options

```txt
Usage: ./setup.sh [options]

Options:
-l, --list            List all available modules
-m, --module <name>   Run only a specific module (e.g., dev)
-r, --resume <name>   Resume installation from a specific module
-h, --help            Show this help message

Examples:
./setup.sh --list
./setup.sh -m graphical
./setup.sh --resume dev
```

## Notes

* A reboot is required to enable NVIDIA drivers and the SDDM service.
* Existing configurations are backed up with the .bak extension.
* On ARM, Ghostty is compiled from the AUR (`ghostty-git`), and the apps only
  published for x86_64 (Discord, JetBrains Toolbox, Yubico Authenticator)
  and the QEMU/KVM host setup are skipped.
