# Architecture

The setup is a Rust binary, `setup`, and a repository of modules. The
binary reads the modules, lets the user pick what to install, and runs the
plan; the modules declare their units in TOML and keep their logic in small
bash hook functions.

This document describes how the code is cut and why, as it stands. Related
documents: `docs/manifest.md` for the format of the modules, the README for
the user's view.

1. [Overview](#1-overview): layout, dependencies, vocabulary, rules
2. [From a manifest to a run](#2-from-a-manifest-to-a-run)
3. [Crates](#3-crates): one section per crate, same shape
4. [The bash side](#4-the-bash-side): the hook contract, the bootstrap
5. [Quality](#5-quality): tests, CI, releases

## 1. Overview

### 1.1 Layout

```
tui/                 the Rust workspace: edition 2024, one crate per responsibility
  model/             the domain, pure: declarations, registry, profiles, selection, plan
  repo/              a repository on disk: manifests, hook scripts, profiles
  host/              this machine: platform, machine, checks before a run, sudo
  journal/           the run folders: plan, statuses, answers, logs, resume
  runner/            running a plan: packages, services, files, hooks
  screens/           the selection screens (ratatui)
  cli/               the binary: arguments, configuration, console, commands
lib/                 the bash the hooks run with: core.sh, ui.sh, platform.sh, hook.sh
modules/<id>/        a module: module.toml, hooks.sh, files/
profiles/            ready-made selections
bootstrap.sh         a fresh machine: git, the released binary, the clone, the run
```

### 1.2 Dependencies

From the bottom up. An arrow reads "is used by".

```
model ──► repo       reads manifests into model declarations
      ──► host       fills model::Platform
      ──► runner     runs the units of a registry ──► uses journal for the run folders
      ──► screens    shows the registry, and the machine of host
journal              plain strings: depends on nothing of the setup
cli ◄── all of them  the only main, the only reader of the environment
```

### 1.3 Vocabulary

| Word          | Meaning                                                                                   | Lives in            |
|---------------|-------------------------------------------------------------------------------------------|---------------------|
| Module        | A folder `modules/<id>/` with its manifest, its hooks and its files.                       | `ModuleDeclaration` |
| Unit          | The one thing that can be picked: packages, services, files and hooks under one id.       | `UnitDeclaration`, `Unit` |
| Fragment      | A `[[unit]]` with `extend` or `override`: what a module adds to, or replaces in, a unit of a module read before. | `Fragment`, `Merge` |
| Variant       | A choice between versions of a file, named `{id}` in a source.                            | `Variant`           |
| Input         | A question answered before the run, read by the hooks as `INPUT_<ID>`.                     | `Input`             |
| Platform      | What the manifests may test about the machine: distro, arch, cpu, gpu...                   | `Platform`, `Condition` |
| Profile       | A ready-made selection: units by pattern, variants, answers, optionally extending another. | `Profile`           |
| Selection     | Units picked, options chosen, questions answered: what the screens edit.                   | `Selection`         |
| Plan          | The steps of a run in order, each with its reason, plus what was left out.                | `Plan`, `Step`      |
| Run           | A folder recording a plan, its statuses, answers and logs; resumable.                     | `journal::Run`      |
| Hook          | A bash function of a module's `hooks.sh`, run after the declared parts of a unit.          | `Hook`, `HookRun`   |

### 1.4 Rules

- `lib.rs` holds `pub use` lines only; modules are private. The public API
  of a crate is what its `lib.rs` names, nothing else.
- A type with an invariant has private fields, a constructor that
  validates, and accessors: `Registry`, `Unit`, `Profiles`, `Condition`,
  `Plan`. The plain values of the manifests have public fields.
- One error enum per crate with `thiserror`; `anyhow` in the binary only.
- The environment is read in one place, `cli::config::Environment`.
- Nothing is hard-coded twice: the platform properties live in
  `model::platform::PROPERTIES`, the bash contract in `runner::contract`,
  the layout of a repository in `repo`.
- `unsafe_code = "forbid"`, `clippy --all-targets -D warnings`,
  `cargo fmt --check`, no `#[allow]`: a lint is fixed, not silenced.
- Tests sit with the code; the integration tests of `repo`, `runner` and
  `cli` run against the real `lib/` and fake tools in a sandbox. Nothing
  ever installs or changes the machine running the tests.

## 2. From a manifest to a run

| Step | What happens                                                                                   | Where                                   |
|------|------------------------------------------------------------------------------------------------|-----------------------------------------|
| 1    | The modules of the public repository, then of the private one, are read into declarations; every source and hook is checked against its module folder. | `repo::Repository::load` |
| 2    | The platform of the machine is read: distro, arch, cpu, gpu, vm, boot loader, file systems.    | `host::probe_platform`                  |
| 3    | Fragments are merged into the units they name; everything is validated; what applies to this platform is computed. | `model::Registry::new` |
| 4    | A profile resolves into a selection, or the screens build one.                                 | `model::Profiles::resolve`, `screens::select` |
| 5    | The plan orders the run: `always` units first, then the selection and what it requires, declaration order breaking ties. | `model::plan::build` |
| 6    | The answers are completed with the defaults, the missing ones asked; the machine is checked.    | `runner::Answers`, `host::check`        |
| 7    | A run folder is opened; the steps not done yet run one by one, logged, recorded, shown.         | `journal::RunStore::create`, `runner::Executor::run` |
| 8    | A failure or Ctrl-C stops the run; `setup resume` runs the same folder again, skipping the steps done. | `journal::RunStore::resumable` |

Variations: `--files-only` keeps the units with files and deploys their
files and hooks without packages, services or checks (`Plan::keeping`,
`ExecConfig.files_only`); `--dry-run` goes through every step without
running anything; `--config <unit>` opens the screens on the variants of a
unit, files only.

## 3. Crates

Each section gives the role of the crate, its public API, what is inside,
and the invariants it holds.

### 3.1 model

The domain, with no file, process or environment access.

| Public item                                   | Purpose                                                                |
|-----------------------------------------------|------------------------------------------------------------------------|
| `Declarations`, `ModuleDeclaration`, `UnitDeclaration`, `Fragment`, `Merge`, `FileEntry`, `Mode`, `Variant`, `Input`, `InputKind`, `InputOption`, `Hook`, `Package`, `Service` | What a reader finds in the manifests, plain values. |
| `Platform`, `Condition`, `Expected`, `ConditionError` | The machine as the manifests see it; `Condition::new` checks a condition against `PROPERTIES`, `holds` evaluates it; `Platform::distributions()`. |
| `Registry`, `Module`, `Unit`, `HookRun`, `RegistryError` | `Registry::new(Declarations, &Platform)`: fragments merged, everything validated, availability and offers computed. |
| `Profile`, `Profiles`, `Resolved`, `ProfileError` | `Profiles::new` (names unique, chains checked), `resolve(name, &Registry)` with `glob` patterns. |
| `Selection`, `InputValue`                     | What the screens edit: units, options, answers (`Text` or `Flag`).      |
| `plan::build`, `Plan`, `Step`, `Reason`       | The ordered run; `Plan::keeping` narrows it.                           |

Inside: `declarations`, `platform`, `registry`, `profile`, `selection`,
`plan`.

Invariants:

- A unit id is unique across modules; a variant or input id within its
  unit; every variant is used by a file; every `{placeholder}` names a
  variant; `parent`, `requires` and `after` name known units, without cycle.
- Fragments apply at the declaration level before validation (`Merged`):
  a fragment's file sources become absolute, its hooks remember their
  module (`HookRun { function, module_root }`), the options it adds to a
  variant remember theirs (`Unit::option_root`). A fragment names a unit
  of a module read before, never of its own; one override per unit.
- `Unit` exposes what applies to the machine only: `packages()`, `aur()`,
  `hooks()`, `hook_runs()`, `available()`, `offered()`, `extended_by()`.
  `Condition::holds` is the one place that knows the platform properties.

### 3.2 repo

A repository on disk, read into declarations and checked against its files.

| Public item                                   | Purpose                                                                |
|-----------------------------------------------|------------------------------------------------------------------------|
| `Repository::open(root)`                      | A folder with `modules/`; the public one also holds `lib/hook.sh` (`hook_script()`). |
| `Repository::declarations()`                  | Every `modules/*/module.toml` in folder order, each module checked against its folder (`module_dir`, `module_script`). |
| `Repository::load(&[Repository])`             | Several repositories in order, the public one first; a module twice is refused; the files of the options a fragment adds are checked in its module. |
| `Repository::profiles()`, `read_profiles`, `write_profile`, `valid_profile_name` | The profiles of a repository, and the user's. |
| `RepoError`                                   | Every mistake with the file it comes from.                              |

Inside: `manifest` (the TOML form as serde DTOs with `deny_unknown_fields`,
and its conversion: a `[[unit]]` is a unit or a fragment, entries have short
forms), `repository` (layout, checks), `profiles`, `error`.

Invariants: a file left directly under `modules/` is a layout error; every
source exists for every combination of the variants it names; every hook
is a function of the module's `hooks.sh`; a fragment sets none of the
fields of a unit.

### 3.3 host

This machine, read from `/proc`, `/sys`, `/etc` and the tools of a minimal
installation. Parsing is separate from reading, and tested.

| Public item                                   | Purpose                                                                |
|-----------------------------------------------|------------------------------------------------------------------------|
| `probe_platform() -> Platform`                | What the manifests test.                                               |
| `probe_machine() -> Machine`, `Usage`         | Host, system, kernel, CPU, GPU, boot loader, virtualization, memory and disk usage, for the first screen. |
| `check(&CheckContext) -> CheckReport`, `Problem`, `Action`, `Network`, `DEFAULT_PACMAN_LOCK` | Distribution, architecture, not root, a terminal, sudo, network, pacman lock. Problems carry their fix; actions (`AskSudoPassword`, `RemovePacmanLock`) are the binary's to take or decline. |
| `authenticate`, `KeepAlive`, `remove_pacman_lock` | `sudo -v`, the rights kept alive during a run, a stale lock removed. |
| `HostError`                                   |                                                                        |

Inside: `platform`, `machine`, `checks`, `sudo`, `probe` (the readers).

Invariant: nothing is printed or asked here; the crate reports, the binary
decides.

### 3.4 journal

The run folders under `~/.local/state/arch-setup/runs/<date>/`. Plain
strings only: the crate knows neither the model nor the machine.

```
meta       profile, started, dry_run, files_only, machine, argv, private, abandoned
plan       "unit <id>" lines, in run order
variants   "<unit> <variant> <option>"
inputs     "<unit> <input> <value>", the secrets left out by the caller
status     "<epoch> unit <id> <status> [code]", appended: the last line of a step wins
setup.log  what the setup printed
steps/     NN-<unit>.log, one per step, attempts appended
```

| Public item                                   | Purpose                                                                |
|-----------------------------------------------|------------------------------------------------------------------------|
| `RunStore::new(state_dir)`, `create(&NewRun)`, `latest()`, `resumable()`, `prune(keep)`, `RUNS_KEPT` | The folders; `latest` links the last real run. |
| `Run`, `Status`                               | `status`, `code`, `record`, `step_log`, `describe`, `abandon`, `is_resumable`. |
| `JournalError`                                |                                                                        |

Invariants: a dry run or a files-only run is never resumed nor the latest
run; a resumable run is neither abandoned nor complete.

### 3.5 runner

Running a plan for one registry on one platform.

| Public item                                   | Purpose                                                                |
|-----------------------------------------------|------------------------------------------------------------------------|
| `contract`                                    | The names shared with `lib/hook.sh` (see 4.1).                         |
| `Answers`                                     | `from_selection` (defaults filled in), `from_recorded` (a resumed run), `missing(&Unit)`, `inputs_without_secrets`. |
| `Commands`                                    | The programs (sudo, bash, pacman, yay, apt-get, systemctl; fakes in the tests) and the commands of a distribution. |
| `Executor::new(ExecConfig, &Registry, &Platform)`, `run(&Run, &Answers, &Interrupt, &mut dyn Observer) -> RunOutcome`, `RunStatus`, `Timing` | The steps not done yet, in order. |
| `Observer`, `StepView`, `StepActions`, `Phase`, `Progress`, `StepOutcome`, `SkipReason`, `Failure` | What the binary is told; a failure is data, its wording is the binary's. |
| `Interrupt`                                   | Ctrl-C, counted.                                                       |
| `RunnerError`                                 |                                                                        |

Inside: `answers`, `commands`, `deploy` (links, copies, folders entry by
entry, backups, permissions, system files through `sudo install`),
`process` (a step command and its log, foreground or background, stopped
by INT, TERM, KILL in turn), `hints` (the probable cause of a failure),
`executor`, `interrupt`, `observer`, `contract`, `error`.

Invariants:

- A step is a unit: packages, aur, services, files, hooks, in this order;
  each hook runs from the `hooks.sh` of the module that declared it.
- Deploying is idempotent: a link already pointing to the source or an
  identical copy is left alone. A folder deployed entry by entry becomes a
  real folder when a link stands in its place.
- Nothing is written through a link into a repository, and a destination
  that is the source itself is refused.
- A package tool is never killed mid-package: Ctrl-C waits for it; a
  second Ctrl-C detaches it.
- `files_only` runs the files and the hooks alone; attended units keep
  their rule (skipped without a terminal or with `--yes`).

### 3.6 screens

The selection screens, ratatui on crossterm, with no disk access: the
binary writes the profile and fetches the private repository.

| Public item                                   | Purpose                                                                |
|-----------------------------------------------|------------------------------------------------------------------------|
| `select(&SelectContext) -> Outcome`           | The event loop; `Outcome::{Quit, Run { profile, selection }, Resume, Save { name, profile, selection }, Private(source)}`. |
| `SelectContext`                               | The registry, the profiles, the machine, the resumable run, the private source, `ascii`, `dry_run`, `files_only`, the units of `--config`. |
| `Palette`, `Glyphs`                           | Colors and symbols, shared with the console of the binary.             |
| `ScreenError`                                 |                                                                        |

Screens, in order: Profile (the machine, an unfinished run, the private
repository, `none`, the profiles), Units (a band per module, parts under
their parent, selected and required marks; for the files alone, the units
with files), Variants (every variant of the planned units, the required
ones included), Answers (text, secret, yes/no, choice), Summary (the steps
with their reason, the units left out). A screen with nothing to show is
skipped; Esc goes back the same way.

Inside: `app` (the state and the keys: cursor and scroll offset per screen
with a margin, filter, text entry, clearing an answer, saving), `rows` (the
lines of each screen from the model), `ui` (the drawing), `theme`.

### 3.7 cli

The binary `setup`. `main.rs` reads the environment, parses the arguments
and calls `app::run`; everything else is in modules.

| Module        | Purpose                                                                                    |
|---------------|--------------------------------------------------------------------------------------------|
| `args`        | clap: `select` (default), `profile <name>`, `resume`, `logs`, `dump`, `new <dir> [--public]`; the global options `--dry-run`, `--files-only`, `--config <unit>` (implies `--files-only`), `--yes`, `--private <url|dir>`, `--repo <dir>`, `--profiles <dir>`, `--ascii`, `--windows`. What does not go together exits with 2. |
| `config`      | `Environment::current()`, the only environment reads (HOME, SETUP_DIR, SETUP_STATE_DIR, XDG folders, TERM, locale, NO_COLOR, SETUP_NO_TTY, PACMAN_LOCK, the terminal); `Config::resolve(&Args, &Environment)`: the repository (`--repo`, `SETUP_DIR`, or found up from the current folder), the folders, the switches. |
| `console`     | `Console`: toned lines copied to the `setup.log` of the run, a status line for the spinner, questions on `/dev/tty` with secrets typed hidden. `RunView` implements the runner's `Observer`: the plan, a line per step, the failure report with the resume command, the summary. |
| `commands`    | `common`: the `Setup` (repositories, platform, registry, profiles merged public < private < user, run store), the checks and their actions, the missing answers, start and resume. `select`, `profile`, `resume`, `logs`, `dump`, `new` (a repository of modules, read back to prove it valid, `--public` with the hook library), `windows`. |
| `private`     | A private repository: a folder used in place, or an HTTPS URL cloned into `~/.local/share/arch-setup/private` with a token asked on the terminal and handed to git through a temporary `GIT_ASKPASS` script; the source remembered in `private.source` and in the `meta` of each run. |

Exit codes: 0 done, 1 failed or refused, 2 a mistake in the arguments,
130 interrupted.

## 4. The bash side

### 4.1 lib/hook.sh and the contract

`lib/hook.sh <module script> <function>` runs one hook: it sources
`lib/core.sh` (paths, exit hooks, strict mode), `lib/ui.sh` (the `log_*`
messages, the status file of a background step) and `lib/platform.sh` (the
helpers: `install_pkg`, `enable_service`, `ensure_line`, kernel command
line and mkinitcpio edits), then the module's `hooks.sh`, and calls the
function. The first failing command ends the step and is named in the log.
A hook asks nothing and is idempotent.

The environment, set by the runner (`runner::contract`):

| Variable                        | Value                                                                 |
|---------------------------------|-----------------------------------------------------------------------|
| `SETUP_DIR`                     | The public repository.                                                |
| `SETUP_MODULE_ROOT`             | The folder of the module of the hook (`modules/<id>`, public or private). |
| `HOST_DISTRO`, `HOST_ARCH`, `HOST_CPU`, `HOST_GPU`, `HOST_VM`, `HOST_BOOTLOADER`, `HOST_APPLE_SILICON`, `HOST_FILESYSTEMS` | The platform; lists space-separated, flags `1` or `0`. |
| `INPUT_<ID>`                    | The answer to each input of the unit.                                 |
| `VARIANT_<ID>`                  | The option chosen for each variant of the unit.                       |
| `SETUP_STEP_LOG`, `SETUP_STEP_STATUS`, `UI_QUIET` | The log of the step, the status file of a background step, quiet mode. |
| `SETUP_DRY_RUN`, `SETUP_ASSUME_YES` | The switches of the run, `1` or `0`.                              |

Markers the runner reads back: `[error] Command failed (code N): cmd` from
`lib/core.sh`, `# ` comment lines of the step log, exit code 130 on an
interruption.

### 4.2 bootstrap.sh

The only other bash. On a fresh machine it refuses root and unknown
architectures, installs git when missing, downloads the released binary for
the architecture and checks its SHA-256, installs it in `~/.local/bin`,
clones the repository of modules (`SETUP_REPO`, default this one) into
`~/.dotfiles` or fast-forwards an existing clone, and starts `setup` with
the arguments given. Tested with bats and fake tools.

## 5. Quality

### 5.1 Tests

`make check` runs shellcheck on the bash, the bats tests (`lib/`,
`bootstrap.sh`) and the Rust workspace (`cargo fmt --check`, clippy with
`-D warnings`, `cargo test --workspace`). The crates test their logic on
fixtures; `repo` loads the real repository; `runner` and `cli` run end to
end in a sandbox with the real `lib/`, fake sudo, pacman, systemctl, curl
and pgrep, an isolated home and state folder.

### 5.2 CI

Two jobs: `arch`, an Arch Linux container on an Ubuntu host (GitHub has no
Arch runner) running `make check` and a release build as a user, since the
setup refuses root; `arm`, the Ubuntu ARM runner for aarch64 (no official
Arch Linux ARM image exists), running the bats tests and the Rust workspace.

### 5.3 Releases

A tag `v<version>`, checked against the workspace version, builds static
musl binaries for x86_64 and aarch64 and publishes them with their SHA-256
sums. The binaries depend on nothing of the host that built them: this is
what the bootstrap downloads.
