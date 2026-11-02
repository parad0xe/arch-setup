# The setup in Rust

A Cargo workspace. Each crate has one responsibility and a small public
API; `cli` holds the binary `setup`.

```
tui/
  Cargo.toml   the workspace: edition 2024, shared dependencies, unsafe_code forbidden
  model/       what the setup is made of, pure: declarations, Registry, Profiles,
               Selection, plan (docs/manifest.md gives the format they read)
  repo/        the repository on disk: manifests (modules/*/module.toml) into declarations,
               checks against the files and the hook scripts, profiles read and written
  host/        this machine: the platform the manifests test, what it is for the
               screens, the checks before a run as data, sudo
  journal/     the run folders: plan, statuses, variants, answers, logs, resume
  runner/      one run: packages, services, files and hooks per unit, logs and
               statuses in the journal, interruption; the environment of lib/hook.sh
  screens/     the selection (ratatui): profile, units, answers, summary
  cli/         the binary setup: arguments (clap), environment and folders,
               console (the observer of a run), commands, private repository
```

From the repository: `make lint-rust test-rust` formats, lints and tests the workspace
(`cli/tests/binary.rs` runs the binary end to end in a sandbox with fake tools);
`cargo build --release --manifest-path tui/Cargo.toml` builds the binary.

```
setup                        the screens, then the run
setup profile <name> [-y]    a profile without the screens
setup resume                 the last unfinished run
setup logs | dump            the last run; the setup as JSON
setup new <dir> [--public]   a new repository of modules
  -n, --dry-run    --files-only    --config <unit>    --private <url|dir>    --repo <dir>    --profiles <dir>    --ascii
```

A dry run in a sandbox, changing nothing:

```
HOME=/tmp/sb/home SETUP_STATE_DIR=/tmp/sb/state tui/target/debug/setup \
  --repo . --profiles /tmp/sb/profiles profile <name> --dry-run --yes
```
