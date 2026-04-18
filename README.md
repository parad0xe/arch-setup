# Arch Linux Setup - Hyprland Edition

This repository contains a set of modular scripts designed to automate
the installation and configuration of a complete Arch Linux environment.

## Features

* Modular Architecture: Scripts divided by theme (Core, Hardware, etc.).
* NVIDIA Optimized: Automatic driver installation and DRM configuration.
* Dotfiles Management: Deployment via symbolic links to ~/.config.
* Complete Environment: Hyprland, Waybar, ZSH, PipeWire, and Bluetooth.

## Project Structure

* install.sh: Main orchestrator and global variables.
* bootstrap.sh: Entry script to clone the repo into ~/.dotfiles.
* modules/: Individual installation scripts.
* dotfiles/: Configurations for Hyprland, Waybar, Mako, Ghostty, etc.

## Configuration

Customize the following variables in install.sh before launching:

* CFG\_TIMEZONE: Your system timezone (e.g., "Europe/Paris").
* CFG\_EMAIL: Email address for Git and SSH key generation.
* CFG\_GIT\_USER: Username for Git configuration.

## Installation

On a fresh Arch Linux installation, run the following command:

```bash
curl -fsSL https://raw.githubusercontent.com/parad0xe/arch-setup/main/bootstrap.sh | bash
```

## Notes

* A reboot is required to enable NVIDIA drivers and the SDDM service.
* Existing configurations are backed up with the .bak extension.
