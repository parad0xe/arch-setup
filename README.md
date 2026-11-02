# Arch Linux Setup - Hyprland Edition

Turns a fresh, minimal Arch Linux into a Hyprland desktop: packages,
services and drivers, shell and development tools, and the configs of this
repository, picked on a few screens or by a profile. Every step is logged,
and a run that stops (a failure, Ctrl-C) is resumed where it was.

## What it installs

Units, grouped by module and picked on the screens or by a profile: the
Hyprland desktop (Waybar, mako, rofi, SDDM, fonts, cursor and icon themes),
hardware services (NetworkManager, PipeWire, Bluetooth, NVIDIA drivers,
microcode, security keys), the shell and terminal tools (Zsh or fish,
Starship, tmux, Vim, yazi), applications (Ghostty, Brave, Nautilus, KeePass...),
development tools (Python, Node.js, Rust, Neovim), dual boot with GRUB,
QEMU/KVM, your settings (SSH key, Git, timezone) and wallpapers. The
`system` units (update, base packages, yay) always run first; the units
that do not apply to the machine are not offered, and what a unit needs
comes with it.

A unit installs its packages, enables its services and copies its configs
into your home (or links them to the repository when it asks for it), some
in variants picked on the screens: keybindings, keyboard layout, Waybar
theme, zshrc...

## Requirements

- A fresh, minimal Arch Linux (x86_64) or Arch Linux ARM (aarch64, e.g.
  Asahi Linux on Apple Silicon).
- A regular user that can use sudo (archinstall creates one), not root: the
  setup deploys the configs into your home. Otherwise, as root, then log in
  again:

  ```bash
  pacman -S sudo
  usermod -aG wheel <user>
  echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
  ```

- Network access.

The setup checks this before running and prints each problem with its fix,
asks for your sudo password once (kept alive for the whole run), and starts
with a full system update.

## Installation

One line on the fresh machine: it installs git, downloads the latest
`setup` release for your architecture and checks it, clones this
repository into `~/.dotfiles` and starts the setup.

```bash
curl -fsSL https://raw.githubusercontent.com/parad0xe/arch-setup/main/bootstrap.sh | bash
```

Arguments after `bash -s --` go to `setup`, e.g. `| bash -s -- profile
parad0xe`. Afterwards, `~/.local/bin/setup` runs from the repository, or
from anywhere with `--repo ~/.dotfiles`. Building it yourself:
`cargo build --release --manifest-path tui/Cargo.toml`.

The screens come in turn; `Enter` goes forward, `Esc` back, `?` lists the
keys.

1. Profile: the selection to start from (`none` starts empty). An unfinished
   run is offered here, and a private repository can be added.
2. Units: `Space` selects a unit, or all the units of a module on its
   heading. What a unit needs is marked and comes with it.
3. Variants: the versions of the configs of every unit that will run, the
   required ones included (keybindings, keyboard layout, Waybar theme,
   zshrc...); `←`/`→` pick one, the default applies otherwise.
4. Answers: the questions of the selected units (Git name and email, the
   email of the SSH key, the timezone...), answered before the run.
5. Summary: everything that will run, in order, with why. `Enter`
   installs, `s` saves the selection as a profile.

A profile is a ready-made selection: `full` (everything, default variants),
`parad0xe` and `kayzzel` come with the repository, and `setup profile
<name>` runs one without the screens. A profile saved from the summary goes
to `~/.local/share/arch-setup/profiles/<name>.toml` (under `XDG_DATA_HOME`
when set), outside the repository, and takes precedence over a repository
profile of the same name.

## What a run does

1. The checks above, the sudo password.
2. The `system` units: full update, base packages, yay.
3. Each selected unit, after the ones it needs: its packages, services and
   configs, then its scripts, behind a spinner with the output in its own
   log. The units that need the terminal (`ssh-key`, `wallpapers-defaults`)
   run in the foreground.
4. A reboot, to apply the drivers, the services and the login screen.

Running the setup again is safe: packages already installed, links already
in place and settings already applied are left as they are. `--dry-run`
shows what would run without changing anything (the screens say so).

## Resuming a run

A failing step stops the run; so does Ctrl-C, which stops the current step
cleanly (a package tool is left to finish its package). Resume it with:

```bash
setup resume
```

The steps already done are skipped, the failed one runs again, then the
rest. Launching `setup` again also offers to resume the unfinished run
before starting a new one; starting a new one leaves it aside. A resume
takes no other option (the run continues as planned) and asks for a new run
when the setup changed since and a step no longer exists.

## Logs and errors

`setup logs` shows the last run: each step, its status and its log. The
ten newest runs are kept in `~/.local/state/arch-setup/runs/<date>/` (under
`XDG_STATE_HOME` when set; `arch-setup/latest` points to the last one). A
run folder holds `setup.log` (what the setup printed), one
`steps/NN-<unit>.log` per step (its full output), and the `plan`, `status`,
`variants` and `inputs` of the run (secrets are never written).

When a step fails, the setup prints the last lines of its log, the failed
command, a probable cause, the path of the full log and the resume command.
Common causes:

- No network or unreachable mirrors: check the connection (`nmcli`, `iwctl`)
  or `/etc/pacman.d/mirrorlist`, then resume.
- `unable to lock database`: another pacman runs, or an interrupted one left
  `/var/lib/pacman/db.lck`; remove it when no pacman runs (the setup offers
  to at start).
- Signature or keyring errors: `sudo pacman -Sy archlinux-keyring`
  (`archlinuxarm-keyring` on ARM), then resume.
- `target not found`: the package is not in the enabled repositories (some
  x86_64 packages do not exist on ARM). A failed AUR build keeps its error
  in the step log and starts over on resume.

## Commands

```txt
setup                      the screens, then the run
setup profile <name>       run a profile without the screens
setup resume               resume the last run where it stopped
setup logs                 show the steps and the logs of the last run
setup dump                 print the platform, the units and the profiles as JSON
setup new <dir> [--public] create a repository of modules (see below)

  -n, --dry-run              show what would run, change nothing
  -y, --yes                  answer the questions with their default and skip the
                             units that need the terminal (with profile or resume)
      --private <URL|DIR>    a private repository read after this one: an HTTPS
                             URL (a token is asked) or a folder
      --repo <DIR>           the setup repository (default: found from the
                             current folder, or SETUP_DIR)
      --profiles <DIR>       where the saved profiles are
      --files-only           deploy the files of the selected units (their variants)
                             and run their hooks: no packages, services nor checks
      --config <UNIT>        redeploy the configs of this unit: the screens open on its
                             variants, files only (repeatable)
      --ascii                plain symbols and borders (the Linux console)
      --windows              what the setup has to say to Windows
```

With `--files-only`, only the configs are deployed: the screens list the
units that have files, a profile picked there brings its variants and
answers without selecting anything (`setup profile <name> --files-only`
deploys all of the profile's units with files), the files are linked or
copied, then the hooks of these units run so
that the configs take effect (Waybar restarts, Git gets its identity),
without installing anything nor checking the machine. Such a run is never
resumed. `setup --config waybar` is the short form for one unit: files
only, the screens open on its variants; pick the theme, `Enter` twice, the
bar is redeployed and restarted.

With `--yes`, nothing is asked: `setup profile full --yes` runs the
profile without the screens, the units that need the terminal are skipped
(run them later from a terminal), and an answer a unit requires must come
from the profile.

## Private repository

What stays out of this public repository (hosts, mounts, keys, credentials)
lives in a second one with the same layout. Add it with `--private`, or from
the first screen: an HTTPS URL is cloned into
`~/.local/share/arch-setup/private` with a token asked on the terminal and
handed to git alone, nothing written; a folder (a USB key) is used in
place. Its units and profiles add up to the public ones, its modules may
extend a public unit (more files, a variant or a shell of their own, a hook) or
replace its configuration, and the setup remembers it for the next
launches.

`setup new ~/private` starts one: the layout, an example module with its
hook script and file, an example profile and a README, checked by the
setup. With `--public` the hook library comes along and the repository
stands alone, as this one does: use it with `setup --repo <dir>`, or on a
fresh machine with the bootstrap and `SETUP_REPO=<owner>/<name>` (the
binary still comes from the releases of this repository).

## Notes

- A config already in your home is replaced, unless its unit asks to keep
  it as `.bak`, `.bak.1`, `.bak.2`... A copy identical to the repository's
  is left alone, so running the setup again changes nothing.
- On ARM, Ghostty is built from the AUR (`ghostty-git`) and rofi from the
  Arch Linux PKGBUILD (the ARM repositories only have rofi 1.7.5, X11 only);
  the apps only published for x86_64 (JetBrains Toolbox, Discord, Yubico
  Authenticator) and the QEMU/KVM host are not offered.
- The output falls back to ASCII symbols on the Linux console (`TERM=linux`)
  or outside a UTF-8 locale, and drops colors when piped or with `NO_COLOR`.

## Development

```bash
make check                        # everything the CI runs: lint and test, bash and Rust
make lint-bash test-bash          # shellcheck, bats
make lint-rust test-rust          # fmt --check and clippy, cargo test
make build                        # the release binary, tui/target/release/setup
make run ARGS="--config waybar"   # build, then start the setup with these arguments
make dry-run ARGS="profile full"  # the same, as a dry run
make clean                        # the build output
```

CI runs it in an Arch Linux container and on an Ubuntu ARM runner (the
aarch64 coverage); a tag `v<version>` releases the static binaries with
their checksums.
`docs/manifest.md` describes the modules (one folder each under `modules/`:
manifest, bash hooks and files), `docs/architecture.md` and `tui/README.md` the Rust workspace.
