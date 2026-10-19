# Arch Linux Setup - Hyprland Edition

This repository contains a set of modular scripts designed to automate
the installation and configuration of a complete Arch Linux environment.

## Features

* Blocks and Profiles: Pick a profile, select the blocks to install and the
  configs to deploy in menus, and check the summary of what will run; the
  blocks and configs they need are added and run in dependency order.
* Optional Configs: The configs of this repository are deployed only when
  selected, with their variants (keybindings, keyboard layout, Waybar theme,
  zshrc, vimrc) picked in the menu.
* NVIDIA Optimized: Automatic driver installation and DRM configuration
  when an NVIDIA GPU is detected.
* ARM Support: Runs on Arch Linux ARM (aarch64, e.g. Asahi Linux on Apple
  Silicon); see the notes for the differences.
* Complete Environment: Hyprland, Waybar, ZSH, PipeWire, and Bluetooth.

## Project Structure

* setup.sh: Main orchestrator (menus, profiles, dependencies) and global
  variables.
* bootstrap.sh: Entry script to clone the repo into ~/.dotfiles.
* modules/core.sh: Shared helpers and the block and config framework.
* modules/: One file per theme (system, hardware, desktop, terminal, app,
  dev, virtualization, settings, wallpapers), declaring its blocks and
  configs.
* profiles/: Ready-made selections of blocks, configs and config variants.
* .config/: Configurations for Hyprland, Waybar, Mako, Ghostty, etc.

## Blocks, Configs and Profiles

The setup runs in three menus, then a summary:

1. Blocks: what to install. Each step of the setup is a block, declared by
   its module. An element has a short id (`desktop`, `shell`, `neovim`,
   `python`...); its components are named after it (`desktop.sddm`,
   `desktop.tools`...), and the `app.*` blocks group the graphical
   applications. The `system` blocks (update, base packages, yay) always run
   first, and the blocks that do not apply to the machine (NVIDIA without an
   NVIDIA GPU, x86_64-only apps on ARM, QEMU inside a VM...) are not offered.
2. Configs: which configs of this repository to deploy, among the ones of
   the programs that will be installed (e.g. `hypr` when `desktop` is
   selected). Under a config, its variants (e.g. the keybindings of `hypr`)
   show their value; `←`/`→` change it.
3. Summary: every block that will run, in run order, then every config
   deployed after the blocks, with why the ones not selected are there
   (always run, needed by a block or a config).

A block or a config declares what it needs (`--needs`): the blocks or
configs without which it would break, added to the selection and run before
it. The dependencies of a config live on the config, not on the block of its
program: Hyprland alone needs no browser, but the `hypr` config needs
`app.brave` for its `Super + W` keybinding, so installing `desktop` without
the `hypr` config installs no browser.

The blocks menu shows the blocks by module. A module with an element named
after it (`desktop`, `wallpapers`) shows that element with its components
under it; the other modules (`app`, `dev`, `hardware`...) get a section line
whose checkbox tells whether all (`[x]`), some (`[-]`) or none (`[ ]`) of
their blocks are selected. Names are shown without the prefix of their
section or element (`sddm` under `desktop`, `ghostty` under `app`).

In the menus, `Tab` selects or unselects a line (a whole section in the
blocks menu), `Enter` goes to the next step and `Esc` goes back. In the
summary, `Enter` installs everything, and `s` saves the selection as a new
profile: it asks for its name and description, then writes
`~/.local/share/arch-setup/profiles/<name>.profile`, outside the repository,
with the selected blocks and configs and the variants (the required blocks
and the ones they need come back on their own). Once the summary is
validated, the install asks only the questions of the selected modules
(SSH email, Git name, timezone, default wallpapers...).

`./setup.sh --list` shows every block by module, whether it is offered on
the machine, the configs and the profiles.

To change the variants of a config already installed, `./setup.sh -c
waybar` opens the configs menu with only that config, its variants on their
current value, and deploys it again on `Enter`: it runs no block and adds
none of the configs it needs. A config whose program is not installed (its
`--program`, e.g. `waybar`) is skipped with a warning naming the block that
installs it, unless that block is given too (`-b desktop -c waybar`).

A profile is a file in `profiles/` (the repository's ones) or in
`~/.local/share/arch-setup/profiles/` (your own ones, which take precedence
over a repository profile of the same name): its first comment line is the
description shown in the menu, `block` and `config` lines select the
matching blocks and configs (shell patterns), and `choice` lines set a
config variant:

```txt
# Hyprland desktop and shell, without dev tools, VMs or optional apps
block desktop*
block shell
config *
choice .config/hypr/conf/keybinds default
```

To add a block, write its function in the module of its theme, with a
comment above it (shown in the menu preview), and declare it at the end of
the file, the element before its components. A config is declared next to
the block of its program:

```bash
block neovim _setup_neovim "Neovim and the tools its config runs"

config nvim .config/nvim .config/nvim "Neovim: plugins, LSP, linters" --block neovim \
    --program nvim \
    --needs python \
    --needs node \
    --then _install_nvim_plugins
```

The options of `block` and `config` are described in `modules/core.sh`. A
new module file starts with `module "<description>"`, its heading in the
menu.

A config gets variants from a choice: a folder of its files holding a
`.choice` file (its description, shown in the menu) and the variants, each
a file (named without its extension: `vim.lua` is the `vim` variant) or a
folder (`vim/`). When the config is deployed, the chosen variant is linked
in the same folder as `selected.<ext>` (a file) or `selected` (a folder),
and the config uses that link: the Hyprland config loads
`conf/keybinds/selected`, a folder variant holding an `init.lua`. When the
source of a config is itself a choice, each variant is a whole version of
the config, and the config is linked to the selected one:

```txt
.config/waybar/
├── .choice        Waybar theme
├── default/       config, style.css
├── glass/         config, style.css
└── selected       → glass/   (~/.config/waybar → .config/waybar/selected)
```

A config declared with `--copy` is copied instead of linked: the zshrc and
the vimrc, edited on each machine, so that these edits stay out of the
repository. Their variants are files (`.config/zshrc/default.zsh`), and the
selected one is copied to `~/.zshrc`. Deploying it again leaves an
identical copy as is and keeps a different one (your edits) as `.bak`, or
as `.bak.1`, `.bak.2`... so that no backup is overwritten.

## Configuration

Nothing needs to be edited before launching: the setup asks for your
personal settings (SSH key email, Git name and email, timezone) during the
install, and the config variants (keybindings, keyboard layout, Waybar
theme, zshrc, vimrc) are picked in the configs menu or set by the profile.

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

Without -b, -m or -c, asks for a profile, then for the blocks to run and the
configs to deploy (the profile's ones selected), and shows what will run
before installing it. The blocks and configs they need are added, every
block runs after the ones it needs, and the configs are deployed after the
blocks.

Options:
  -p, --profile <name>   Use this profile instead of asking for one (from
                         ~/.local/share/arch-setup/profiles, where the menu
                         saves them, or else from profiles/)
  -b, --block <pattern>  Run only the matching blocks and the ones they need,
                         without the menus (e.g. neovim, "app.*"); can be
                         repeated
  -m, --module <name>    Same for the blocks of modules/<name>.sh; can be
                         repeated
  -c, --config <pattern> Show only the matching configs whose program is
                         installed in the configs menu, to pick their
                         variants, and deploy them, without running any
                         block nor adding the configs they need (e.g.
                         waybar); can be repeated
  -r, --resume <block>   Skip the blocks that run before this one
  -l, --list             List the blocks, the configs and the profiles
  -h, --help             Show this help message

Examples:
  ./setup.sh -p desktop
  ./setup.sh -m wallpapers
  ./setup.sh -b neovim -b "app.*"
  ./setup.sh -c hypr -c waybar
  ./setup.sh -p full --resume shell
```

## Notes

* A reboot is required to enable NVIDIA drivers and the SDDM service.
* Existing configurations are backed up with the .bak extension (.bak.1,
  .bak.2... for a copied config whose .bak already exists).
* On ARM, Ghostty is compiled from the AUR (`ghostty-git`) and rofi 2 from
  the Arch Linux PKGBUILD (the ARM repositories only have rofi 1.7.5, X11
  only); the apps only published for x86_64 (Discord, JetBrains Toolbox,
  Yubico Authenticator) and the QEMU/KVM host setup are not offered.
