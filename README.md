# Arch Linux Setup - Hyprland Edition

This repository contains a set of modular scripts designed to automate
the installation and configuration of a complete Arch Linux environment.

## Features

* Blocks and Profiles: Pick a profile, then select the blocks to install in
  a menu and check the summary of what will run; the blocks they need are
  added and run in dependency order.
* NVIDIA Optimized: Automatic driver installation and DRM configuration
  when an NVIDIA GPU is detected.
* ARM Support: Runs on Arch Linux ARM (aarch64, e.g. Asahi Linux on Apple
  Silicon); see the notes for the differences.
* Dotfiles Management: Each block links the configs of what it installs
  into ~/.config.
* Complete Environment: Hyprland, Waybar, ZSH, PipeWire, and Bluetooth.

## Project Structure

* setup.sh: Main orchestrator (menus, profiles, dependencies) and global
  variables.
* bootstrap.sh: Entry script to clone the repo into ~/.dotfiles.
* modules/core.sh: Shared helpers and the block framework.
* modules/: One file per theme (system, hardware, desktop, terminal, app,
  dev, virtualization, config, wallpapers), declaring its blocks.
* profiles/: Ready-made selections of blocks and config variants.
* .config/: Configurations for Hyprland, Waybar, Mako, Ghostty, etc.

## Blocks and Profiles

Each step of the setup is a block, declared by its module:

* An element has a short id (`desktop`, `shell`, `neovim`, `python`...); its
  components are named after it (`desktop.sddm`, `desktop.tools`...). The
  `app.*` blocks group the graphical applications.
* The menu offers the elements and their optional components. A component
  its element needs (e.g. `desktop.hypr-tools`) is installed with it; the
  `system` blocks (update, base packages, yay) always run first.
* A block declares the blocks without which its config would break
  (`--needs`, e.g. `desktop` needs `app.ghostty` for its terminal
  keybinding): they are added to the selection and run before it. Blocks
  that do not apply to the machine (NVIDIA without an NVIDIA GPU, x86_64-only
  apps on ARM, QEMU inside a VM...) are not offered.

In the menu, `Tab` selects or unselects a block (`[x]` / `[ ]`) and `Enter`
shows the summary: every block that will run, in run order, with why the
ones not selected are there (always run, needed by another block). `Enter`
installs them, `Esc` goes back to the selection.

`./setup.sh --list` shows every block, its module and whether it is offered
on the machine.

A profile is a file in `profiles/`: its first comment line is the
description shown in the menu, `block` lines select the matching blocks (shell
patterns), and `choice` lines set a config variant instead of asking for it:

```txt
# Hyprland desktop and shell, without dev tools, VMs or optional apps
block desktop*
block shell
choice .config/hypr/conf/keybinds default
```

To add a block, write its function in the module of its theme, with a
comment above it (shown in the menu preview), and declare it at the end of
the file, the element before its components:

```bash
block neovim _setup_neovim "Neovim with its config and plugins" \
    --needs python \
    --needs node
```

The options of `block` are described in `modules/core.sh`.

## Configuration

Nothing needs to be edited before launching: the setup asks for your
personal settings (SSH key email, Git name and email, timezone) and lets you
choose between config variants (keybindings, keyboard layout), unless the
profile sets them.

Machine-specific SSH settings (hosts, extra keys) go in `~/.ssh/config.d/`,
which is included by the versioned SSH config but never versioned itself.

Wallpapers are not stored in this repository: the setup clones a wallpapers
repository (asked at setup, `CFG_WALLPAPERS_REPO` in `setup.sh` by default)
and copies its images and videos (jpg, jpeg, png, webp, mp4) into
`~/Pictures/wallpapers`, then lets you pick the default wallpapers (fzf with
an image preview): the same one for the desktop, lock and login screens, or
one each. Run
`./setup.sh -m wallpapers` to deploy or pick them again; the selector
(`CTRL + Space`) changes them at any time.

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

Without -b or -m, asks for a profile, then for the blocks to run with the
profile's ones selected, and shows what will run before installing it. The
blocks they need are added, and every block runs after the ones it needs.

Options:
  -p, --profile <name>   Use this profile instead of asking for one
  -b, --block <pattern>  Run only the matching blocks and the ones they need,
                         without the menus (e.g. neovim, "app.*"); can be
                         repeated
  -m, --module <name>    Same for the blocks of modules/<name>.sh; can be
                         repeated
  -r, --resume <block>   Skip the blocks that run before this one
  -l, --list             List the blocks and the profiles
  -h, --help             Show this help message

Examples:
  ./setup.sh -p desktop
  ./setup.sh -m wallpapers
  ./setup.sh -b neovim -b "app.*"
  ./setup.sh -p full --resume shell
```

## Notes

* A reboot is required to enable NVIDIA drivers and the SDDM service.
* Existing configurations are backed up with the .bak extension.
* On ARM, Ghostty is compiled from the AUR (`ghostty-git`) and rofi 2 from
  the Arch Linux PKGBUILD (the ARM repositories only have rofi 1.7.5, X11
  only); the apps only published for x86_64 (Discord, JetBrains Toolbox,
  Yubico Authenticator) and the QEMU/KVM host setup are not offered.
