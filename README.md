# Arch Linux Setup - Hyprland Edition

This repository contains a set of modular scripts designed to automate
the installation and configuration of a complete Arch Linux environment.

## Features

* Modular Architecture: Scripts divided by theme (Core, Hardware, etc.).
* NVIDIA Optimized: Automatic driver installation and DRM configuration.
* Dotfiles Management: Deployment via symbolic links to ~/.config.
* Complete Environment: Hyprland, Waybar, ZSH, PipeWire, and Bluetooth.

## Project Structure

* setup.sh: Main orchestrator and global variables.
* bootstrap.sh: Entry script to clone the repo into ~/.dotfiles.
* modules/: Individual installation scripts.
* .config/: Configurations for Hyprland, Waybar, Mako, Ghostty, etc.

## Configuration

Customize the following variables in `setup.sh` before launching:

* CFG\_TIMEZONE: Your system timezone (e.g., "Europe/Paris").
* CFG\_EMAIL: Email address for Git and SSH key generation.
* CFG\_GIT\_USER: Username for Git configuration.

## Installation

On a fresh Arch Linux installation, run the following command:

```bash
git clone git@github.com:parad0xe/arch-setup.git ~/.dotfiles
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
