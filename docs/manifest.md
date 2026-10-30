# Module manifests

What the setup can install is declared in TOML manifests, one per module,
read by setup. Bash is left to hooks: functions run after the declared
parts of a unit, where real logic remains.

Status: validated on 2026-10-30; the modules and profiles are converted and
setup reads them (the `repo` crate checks them against the files).

## Files

```
modules/<module>/module.toml   the module: its units
modules/<module>/hooks.sh      optional: the hook functions of that module
modules/<module>/files/        what its units deploy (the `source` of their files)
profiles/<name>.toml           a profile of the repository
~/.local/share/arch-setup/private/
                           a private repository, same layout, read after
                           this one (see Private repository)
~/.local/share/arch-setup/profiles/<name>.toml
                           a profile of the user; wins over the repository
                           profiles of the same name
```

A module is a folder of `modules/`, named by its id; it holds everything of
its own, so that it can move from one repository to another as it is.
Modules are listed in folder name order, the public repository first; units
in declaration order. Both orders are the default run order and the order
of the screens.

## A module

```toml
[module]
name = "Desktop"                       # one line, the heading of its units
about = "Hyprland desktop: Hyprland, Waybar, mako, polkit agent"   # optional

[[unit]]
# ... see below, repeated
```

## A unit

A unit is the one thing that can be picked: a program with its config, a
service, a setting. It installs packages, enables services, deploys files
and runs a hook, in this order.

| Field      | Type                 | Meaning                                                                 |
|------------|----------------------|-------------------------------------------------------------------------|
| `id`       | string, required     | Unique across all modules. `^[a-z][a-z0-9-]*$`.                          |
| `name`     | string, required     | One line, shown in the lists.                                           |
| `about`    | string               | A paragraph, shown in the details.                                      |
| `parent`   | unit id              | The unit is a part of that unit of the same module (shown in its tree). |
| `always`   | bool                 | Runs in every run, first. Never offered.                                |
| `attended` | bool                 | Its hook runs a tool that needs the terminal (a security key asking for its PIN). Skipped without one, or with `--yes`. |
| `when`     | table                | Conditions on the machine; all must hold. See Conditions.               |
| `requires` | list of unit ids     | Added to the run when they apply to the machine, and run before.        |
| `after`    | list of unit ids     | Run before when selected too; not added.                                |
| `packages` | list of packages     | Installed from the repositories.                                        |
| `aur`      | list of packages     | Installed from the AUR with yay.                                        |
| `services` | list of services     | Enabled with systemctl.                                                 |
| `files`    | list of files        | Deployed into the home folder. See Files.                               |
| `variants` | list of variants     | Choices between versions of its files. See Variants.                    |
| `inputs`   | list of inputs       | Questions answered before the run. See Inputs.                          |
| `hooks`    | list of hooks        | Functions of the module's `hooks.sh`, run last, in order. See Hooks.    |

A unit declares at least one of `packages`, `aur`, `services`, `files`,
`hooks`.

### Parts

`parent` groups optional pieces under a unit: `sddm`, `cursor`, `icons`
under `desktop`. A part that its parent `requires` is installed with it and
not offered on its own; the other parts are offered as options of the
parent. A part may not itself have parts.

### Conditions

`when` is a table of conditions on the platform. Each key names a property
of the platform; the value is the value it must have, or a list of accepted
values. A unit whose `when` does not hold is unavailable: not offered, not
added by `requires`.

| Property        | Values                                    | Read from                                                   |
|-----------------|-------------------------------------------|-------------------------------------------------------------|
| `distro`        | `"arch"`, `"ubuntu"`                      | `/etc/os-release` (`ID`)                                    |
| `arch`          | `"x86_64"`, `"aarch64"`                   | the kernel (`uname -m`)                                     |
| `cpu`           | `"intel"`, `"amd"`, `"apple"`, `"other"`  | `/proc/cpuinfo` vendor, `/proc/device-tree/compatible`      |
| `gpu`           | list of `"nvidia"`, `"amd"`, `"intel"`    | PCI vendor [repo](../tui/repo)ids under `/sys/bus/pci/devices`                 |
| `vm`            | `true`, `false`                           | `systemd-detect-virt --vm`                                  |
| `apple_silicon` | `true`, `false`                           | `/proc/device-tree/compatible` (`apple,arm-platform`)       |
| `bootloader`    | `"grub"`, `"systemd-boot"`, `"none"`      | `/etc/default/grub` and `grub-mkconfig`, `/boot/loader`     |
| `filesystems`   | list of types, e.g. `"ntfs"`, `"btrfs"`   | `lsblk -nro FSTYPE`                                         |

For a list property, the condition holds when the list contains the value
(or one of the values). Examples: `when = { gpu = "nvidia" }`,
`when = { arch = "x86_64", vm = false }`,
`when = { bootloader = "grub", apple_silicon = false, vm = false }`.

The same conditions apply to a package entry (below), so that one unit
installs `intel-ucode` or `amd-ucode` according to the CPU, or `openssl` on
Arch and `libssl-dev` on Ubuntu. A unit or a package without a `distro`
condition applies to every distribution.

### Packages and services

An entry of `packages` or `aur` is a package name, a table
`{ name = "...", when = { ... } }` for a package of some machines only, or
`{ names = ["...", "..."], when = { ... } }` for several under one
condition:

```toml
packages = [
  "git",
  { names = ["openssl", "base-devel"], when = { distro = "arch" } },
  { names = ["libssl-dev", "build-essential"], when = { distro = "ubuntu" } },
]
```

Packages are installed by the package manager of the distribution: pacman
on Arch Linux, apt on Ubuntu. `aur` applies to Arch Linux only, and is
ignored elsewhere. With pacman, the packages already installed are left
alone (`--needed`) and conflicts are resolved in favor of the declared
package: an installed package that conflicts with a declared one is removed
(`--ask=4`). `nvidia-open-dkms` thus replaces `nvidia`, and `pipewire-jack`
replaces `jack2`.

An entry of `services` is a service name, or a table
`{ name = "...", now = true, force = true }`: `now` starts it as well,
`force` replaces a service of the same role (`sddm` as display manager).

### Files

```toml
files = [
  { source = "files/mako", target = ".config/mako" },
  { source = "files/hypr", target = ".config/hypr", contents = true, mode = "symlink" },
  { source = "files/zshrc/{zshrc}.zsh", target = ".zshrc", backup = true },
  { source = "files/bin/{scripts}", target = ".local/bin", contents = true, permissions = "755" },
]
```

| Field        | Default  | Meaning                                                                      |
|--------------|----------|------------------------------------------------------------------------------|
| `source`     | required | A file or folder, relative to the module's folder (`files/...`). May name variants: `{id}`. |
| `target`     | required | Where it goes, from the home folder.                                         |
| `mode`       | `"copy"` | `"copy"`: a copy. `"symlink"`: a symbolic link to the repository, for a config edited in place. |
| `contents`   | `false`  | For a folder: each of its entries (hidden ones excepted) is deployed into the target folder, which keeps its other files. |
| `backup`     | `false`  | `true` keeps a different existing file or folder as `.bak` (`.bak.1`, ...) instead of replacing it. |
| `permissions` |         | The permissions of the copied files, octal: `"600"` for a key, `"755"` for scripts (copies only). |

An absolute `target` names a system file (`/etc/samba/nas.cred`): copied
with sudo, owned by root, `mode = "copy"` and `permissions` required. Files
made of lines (`/etc/fstab`, `/etc/hosts`) are never replaced: a hook adds
their lines with `ensure_line` (see Hooks).

Deploying is idempotent: a link already pointing to the source, or a copy
identical to it, is left alone. Nothing is written into a repository through
a link: a target whose folder links into one is refused (extend the unit
instead, see Fragments).

### Variants

```toml
variants = [
  { id = "keybinds", name = "Hyprland keybindings", options = ["default", "vim"] },
  { id = "theme",    name = "Waybar theme",         options = ["default", "glass"], default = "glass" },
]
```

A variant is a choice between versions of a file or folder. Its `id` is
used as `{id}` in the `source` of the unit's files; the chosen option
replaces it. `default` is the option used when neither the profile nor the
user picks one: `"default"` when the options have it, else the first.

The deployed file is the chosen version itself. The repository holds no
selection state: the `.choice` files and `selected` links of the current
setup disappear.

### Inputs

```toml
inputs = [
  { id = "email",  prompt = "Email of the SSH key", required = true },
  { id = "fido",   prompt = "Use a security key (FIDO2)?", kind = "bool", default = false },
  { id = "passphrase", prompt = "Passphrase (empty for none)", kind = "secret" },
]

# A longer input as its own table, after the other keys of the unit
[[unit.inputs]]
id = "repo"
prompt = "Wallpapers repository"
kind = "choice"
custom = true
default = "https://github.com/kayzzel/wallpapers"
options = [{ name = "kayzzel's wallpapers", value = "https://github.com/kayzzel/wallpapers" }]
```

| Field      | Default  | Meaning                                                   |
|------------|----------|-----------------------------------------------------------|
| `id`       | required | `^[a-z][a-z0-9_]*$`, unique in the unit.                  |
| `prompt`   | required | The question.                                             |
| `kind`     | `"text"` | `"text"`, `"bool"`, `"secret"` (not echoed, not logged), `"choice"` (with `options`). |
| `default`  |          | The answer when none is given (`--yes`, or Enter).        |
| `required` | `false`  | An empty answer is refused (`text` only).                 |
| `options`  |          | The proposed answers (`choice` only): values, or `{ name, value }` tables when the value needs a label. |
| `custom`   | `false`  | A value outside the options may be typed (`choice` only). |

Inputs are answered before the run: on the inputs screen, in the profile, or
by their default. A run never asks anything: `--yes` means "every default".
The hook receives the answers as `INPUT_<ID>` (upper case): `INPUT_EMAIL`,
`INPUT_FIDO` (`1` or `0`), `INPUT_PASSPHRASE`.

### Hooks

`hooks` lists functions of the module's `hooks.sh`, run in order after the
packages, services and files of the unit, by `lib/hook.sh <module script>
<function>`, each as its own sub-step of the log. An entry is a function name, or a table
`{ run = "build_rofi", when = { arch = "aarch64" } }` that runs it on some
machines only: what depends on the machine is declared here, so that the
function is written for the machines it runs on; a hook only checks the
current state (already installed, a session running).

```toml
hooks = ["setup_libvirt", { run = "build_rofi", when = { arch = "aarch64" } }]
``` The script sources
`lib/ui.sh` (the `log_*` functions), `lib/platform.sh` (`install_pkg`,
`install_aur_pkg`, `enable_service`, `kernel_cmdline_add`,
`mkinitcpio_*`...) and the module file, exports the environment below and
calls the function under `set -Ee` with the error trap: the first failing
command ends the step, and is named in the log.

| Variable            | Value                                                      |
|---------------------|------------------------------------------------------------|
| `SETUP_DIR`         | The public repository.                                     |
| `SETUP_MODULE_ROOT` | The folder of the module (`modules/<id>`, public or private): its `files/` are there. |
| `HOST_DISTRO`, `HOST_ARCH`, `HOST_CPU`, `HOST_GPU`, `HOST_VM`, `HOST_BOOTLOADER`, `HOST_APPLE_SILICON`, `HOST_FILESYSTEMS` | The platform, lists space-separated, booleans `1`/`0`. |
| `INPUT_<ID>`        | The answer to each input of the unit.                      |
| `VARIANT_<ID>`      | The option chosen for each variant of the unit.            |

A hook never asks a question, and must be idempotent: run twice, it changes
nothing the second time. For the files made of lines, `lib/platform.sh`
gives `ensure_line <file> <line> [key]`: the line is added when missing,
and with a key (a regex, e.g. the mount point of an fstab entry) a line
matching it is replaced rather than kept next to the new one. In a dry run, hooks are not run; the plan says which would.

The one exception is a tool that talks to the user itself: `ssh-keygen`
with a security key asks for its PIN and a touch. Such a unit is
`attended = true`: its hook runs in the foreground with the terminal, and
the unit is skipped when there is none (or with `--yes`). Hooks are named
without a leading underscore; the helper functions they call keep it.

## Fragments: extend and override

A `[[unit]]` table with `extend` or `override` in place of an `id` is a
fragment: it changes a unit of a module read before it, typically a public
unit from a private repository. It has no `name`, `parent`, `requires`,
`after`, `always` or `attended`: the unit keeps its identity, its place and
its conditions.

```toml
# private/modules/work/module.toml
[[unit]]
extend = "desktop"
when = { gpu = "nvidia" }                  # applies on these machines only
files = [
  { source = "files/hypr/local.lua", target = ".config/hypr/local.lua" },
  { source = "files/hypr/keybinds/{work}.lua", target = ".config/hypr/keybinds.lua" },
]
variants = [{ id = "work", name = "Work keybindings", options = ["laptop", "desk"] }]
hooks = ["announce_work"]                  # a function of this module's hooks.sh

[[unit]]
extend = "terminal"
variants = [{ id = "zshrc", options = ["work"], default = "work" }]   # more options for a variant of the unit
```

`extend` adds to the unit: packages, `aur`, services, inputs, variants and
hooks come on top of the unit's. Its files are added too, except that a
file whose `target` the unit already deploys replaces that entry (one
target, one owner); a variant of the unit that no file names any more
disappears with the file it served. Above, `keybinds.lua` now comes from
the private module with its `work` variant, and the public `keybinds`
variant is gone.

A variant with the id of one of the unit's variants adds its options to it
(a `name` is then not needed, a `default` becomes the variant's). The files
of these options live in the fragment's module, at the path the unit's
files name: for `files/zshrc/{zshrc}.zsh`, the `work` option is
`files/zshrc/work.zsh` of the fragment's module. An option the unit already
has is refused.

`override` replaces the configuration of the unit: its files, variants,
inputs and hooks are the fragment's, and only them. The packages, `aur`
packages and services stay those of the unit (and the fragment may add
some): replacing the Hyprland config does not drop the `hyprland` package.

The sources of a fragment's files are read in the fragment's module
folder, its hooks in its `hooks.sh`; `SETUP_MODULE_ROOT` names that folder
for them. Profiles, the screens and the plan see the unit as merged:
`"desktop.work" = "desk"` is a valid variant of a private profile. `dump`
and the details of a unit name the modules that extended it. Several
fragments may extend a unit; one at most may override it.

## Private repository

What is private (hosts, mounts, machine-specific files) or sensitive (keys,
credentials) lives in a second repository with the same layout, outside the
public one. It is read after the public repository: its modules and units
add up (unit and module ids are global: a duplicate names both
repositories), its units may `requires` public ones, never the other way
round, and its profiles win over the public ones of the same name, the
user's profiles over both.

```
private/
  modules/mounts/module.toml   units: nas (cifs-utils, credentials file, fstab hook)
  modules/mounts/hooks.sh      mount_nas: ensure_line /etc/fstab ... key /mnt/nas
  modules/mounts/files/nas.cred
  modules/hosts/module.toml    units: ssh-hosts (requires ssh; keys and hosts, 600)
  modules/hosts/files/ssh/...
  profiles/home.toml           extends = "parad0xe", units = ["nas", "ssh-hosts"], [inputs]
```

A private module extends or overrides public units with fragments (see
above) and adds its own units beside them.

Starting one: `setup new <folder>` creates this layout with an example
module, profile and README, read back by the setup so that it is valid
(`--public` adds the hook library `lib/`, for a repository standing alone,
used with `--repo` or cloned by the bootstrap with `SETUP_REPO=owner/name`).

Getting it onto a machine that has nothing yet: `setup --private <url
or folder>`, or the "Private repository" line of the first screen. An
HTTPS URL is cloned into `~/.local/share/arch-setup/private` with a token
asked as a secret and handed to git alone (`GIT_ASKPASS`): nothing in the
shell history, the logs or the disk. A folder (a USB key; the ones found
under `/run/media` are proposed) is used in place. An SSH URL is refused
while the machine has no key. The source is remembered and pulled quietly
on the next launches; the private root goes into the meta of each run so
that a resume finds the same units. Secrets are never logged: the copied
files are named, not shown, and secret inputs stay out of the run folder.

## A profile

```toml
# profiles/parad0xe.toml
about = "parad0xe's setup: default keybindings, UK and US layouts"
extends = "full"
exclude = ["discord", "krita"]

[variants]
"desktop.keybinds" = "default"
"desktop.keyboard" = "default"
"shell.zshrc" = "parad0xe"
"vim.vimrc" = "parad0xe"
"bin.scripts" = "parad0xe"
```

| Field      | Meaning                                                                        |
|------------|--------------------------------------------------------------------------------|
| `about`    | One line, shown in the profiles list.                                          |
| `extends`  | Another profile, resolved first. Chains allowed, cycles refused.               |
| `units`    | Unit ids or patterns (`*`, `?`, `[...]`) added to the selection.               |
| `exclude`  | Unit ids or patterns removed from it, after `units`.                           |
| `variants` | `"unit.variant" = "option"`.                                                   |
| `inputs`   | `"unit.input" = value`.                                                        |

The name of a profile is its file name. Only offered units are selectable:
units that run always are implicit, unavailable ones are ignored. Variants
and inputs of the extended profile apply unless overridden.

## From a selection to a run

1. The selection holds offered units, the option of each variant and the
   answer of each input.
2. The plan adds the units the selected ones `require`, recursively, when
   they are available; a required unit that is not available is noted and
   left out. The `always` units are added.
3. Order: `always` units first, in declaration order; then the others so
   that a unit comes after what it `requires` and what it is `after`;
   declaration order breaks ties. A cycle is an error.
4. A unit is one step of the run. Its parts run in order: packages, aur,
   services, files, hooks. A failing part fails the step; the run stops and
   can be resumed at that step. With `--files-only`, the units with files
   deploy them (with their variants) and run their hooks, nothing else: no
   packages, services nor checks, the units without files are left out, and
   the run is never resumed.
5. The run folder records the plan (`unit <id>` lines), the variants, the
   inputs (secrets excepted), the status of each step and its log, as
   today.

The state of a unit on the machine is read from its declared parts:
installed packages (`pacman -Q`), enabled services, deployed files (a link
to the source, or an identical copy). A unit is shown installed, partial or
absent; a unit with only hooks is shown as unknown. A dry run prints, for
each step, the packages it would install, the services it would enable, the
files it would deploy and the hooks it would run.

## Validation

Reading the manifests fails, with the file and line, when:

- an `id` is malformed or declared twice (units across modules, variants
  and inputs within a unit);
- `parent` names a unit of another module, the unit itself, or a part;
- `requires` or `after` names an unknown unit;
- `when` uses an unknown fact, or a value of the wrong type;
- a package or service name is empty or repeated;
- a file `source` does not exist in its repository (for every option of
  the variants it names), a `target` is empty or holds `..`, `contents` is
  set on a file, `permissions` on a link, a system file (absolute target)
  is not copied with permissions;
- a variant has no option, a `default` outside its options, or is used by
  no file; a `{placeholder}` names no variant of the unit;
- an input of kind `choice` has no options, or a `default` outside them
  without `custom`;
- a hook names a function the module's `hooks.sh` does not define, or a
  hook is listed twice;
- a file lies directly under `modules/` (a module is a folder holding
  `module.toml`);
- a `[[unit]]` has none or several of `id`, `extend` and `override`, a unit
  has no `name`, or a fragment sets a field of a unit (`name`, `about`,
  `parent`, `always`, `attended`, `requires`, `after`);
- a fragment names a unit no module read before declares, a unit of its own
  module, or a unit another module already overrides; it adds an option a
  variant already has, or a new variant without a name, or an option whose
  file is missing from its module;
- a unit declares nothing to do.

A profile fails when `extends` is unknown or cyclic, or when a variant or
input names an unknown unit, variant, input or option. A pattern matching
no unit is a warning.

## Appendix A: the converted modules and profiles

The ten modules are converted, each a folder of `modules/`: `module.toml`
holds the units, `hooks.sh` the hooks (700 lines, from 1 400), `files/` what
the units deploy (the former `.config/`). `settings` became `user` and
`timezone` moved to `system`. The profiles are `profiles/full.toml`,
`profiles/kayzzel.toml` and `profiles/parad0xe.toml`.
Beyond the mapping of appendix C:

- The Hyprland config is part of the `desktop` unit, so the parts it runs
  (`hypr-tools`, `desktop-tools`, `connectivity`, `wallpaper-engines`) come
  with `desktop` and are no longer offered separately; `sddm`, `cursor`,
  `icons` and `ddcutil` stay optional.
- The `ssh` block becomes two units: `ssh` (the client config) and
  `ssh-key` (the key, attended because of the security key).
- `wallpapers-defaults` keeps its fzf picker as an attended unit: the
  wallpapers to pick from exist only once the `wallpapers` unit copied
  them, so the choice cannot be an input. Its `same` input replaces the
  "same wallpaper everywhere?" question.
- `timezone` keeps the current zone when its input is empty; `clock`
  defaults to UTC instead of the current setting.
- Waybar is a part of `desktop` picked on its own (`waybar`): restarted
  when it runs, and started when its `start_waybar` input says so; the "Do you want to configure X?" questions
  are gone, picking the unit is the answer.
- A variant with one option (`tmux`) is a plain file.

## Appendix B: changes outside the manifests

Repository:

- `.config/hypr/hyprland.lua`: `require_choice("conf.keyboard")` and
  `require_choice("conf.keybinds")` became `require("keyboard")` and
  `require("keybinds")` (done): the deployed `~/.config/hypr` is a folder of links
  (`contents = true`) holding `keybinds.lua` and `keyboard.lua`, the
  chosen variants. The variant files stay in `conf/keybinds/` and
  `conf/keyboard/`.
- The nine `.choice` files are removed, and the `selected`, `selected.*`
  patterns of `.gitignore` with them (done). The `selected*` links present in a
  working copy are removed by hand once (they are not tracked).
- The other variants (waybar theme, nvim config, fastfetch theme, bin,
  zshrc, vimrc, tmux) change nothing in their files: the chosen folder or
  file is deployed directly.
- The hook scripts lost their `module`, `block` and `config` lines and the
  functions made of `install_pkg` and `enable_service` only; the remaining
  functions lost their leading underscore and their questions (done).
- `lib/ui.sh` keeps the messages only; `lib/platform.sh` the helpers of
  the hooks; `lib/core.sh` the paths, the exit hooks and the strict mode.
  `lib/deploy.sh`, `lib/registry.sh`, `lib/plan.sh`, `lib/profiles.sh`,
  `lib/menu.sh`, `lib/state.sh`, `lib/runner.sh`, `lib/preflight.sh`,
  `lib/step.sh` and `setup.sh` are removed with their tests; `lib/hook.sh`
  is added; `bootstrap.sh` downloads the released setup (done).
- The README describes units and profiles instead of blocks and configs
  (done).

Behavior:

- Installing a program and deploying its config is one choice. A unit
  whose config needs other units `requires` them: they come with it.
- No question during a run. The questions of `ssh` (email, security key,
  passphrase), `git` (name, email, branch), `timezone` (zone) and the
  wallpaper units become inputs, answered before the run; the "Do you want
  to configure X?" questions disappear, since picking the unit is the
  answer.
- Conflicting packages are replaced without asking.
- Files are copied unless a unit asks for `mode = "symlink"`, and an
  existing file is replaced unless it asks for `backup = true`
  (2026-10-30; links and backups were the defaults before).
- The run folders record `unit <id>` steps; the runs of the current format
  cannot be resumed by the new setup.

## Appendix C: from the current declarations

| Today                                        | Manifest                                              |
|----------------------------------------------|-------------------------------------------------------|
| `module "desc"`                              | `[module] name, about`                                |
| `block id fn "desc"`                         | `[[unit]] id, name, about, hooks`                     |
| `block elem.part ...`                        | `id = "part"`, `parent = "elem"`                      |
| `--required`                                 | `always = true`                                       |
| `--if fn`, `--unless fn`                     | `when = { fact = value }`                             |
| `--needs id`                                 | `requires = ["id"]`                                   |
| `--after id`                                 | `after = ["id"]`                                      |
| `--interactive`                              | `inputs`                                              |
| `config id src dst "desc" --block b`         | an entry of `files` in unit `b`                       |
| `config ... --needs id`                      | `requires` of that unit                               |
| `config ... --needs-config c`                | `requires` of the unit holding `c`                    |
| `config ... --program cmd`                   | removed (no config-only mode)                         |
| `--copy`, `--content-only`, `--without-backup`, `--executable` | `mode = "copy"`, `contents = true`, `backup = false`, `permissions = "755"` |
| `--then fn`                                  | `hooks`                                               |
| `.choice` folder, `selected` link            | `variants`, `{id}` in `source`                        |
| `block pattern`, `config pattern` (profile)  | `units = [...]`                                       |
| `choice folder variant` (profile)            | `[variants] "unit.id" = "option"`                     |
| `install_pkg a b` in a function              | `packages = ["a", "b"]`                               |
| `install_aur_pkg a`                          | `aur = ["a"]`                                         |
| `enable_service s`, `systemctl enable --now` | `services = ["s"]`, `{ name = "s", now = true }`      |
