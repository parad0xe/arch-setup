//! A new repository of modules, private by default: the layout, an example
//! module with its hook script and its file, an example profile and a
//! README; with `--public`, the hook library of this repository as well, so
//! that it stands alone. The result is read back as the setup reads it, so
//! that it is known valid.

use std::fs;
use std::path::Path;
use std::process::{Command, ExitCode, Stdio};

use anyhow::{Context, Result, bail};
use model::{Profiles, Registry};
use repo::Repository;

use crate::config::Config;
use crate::console::Console;

const DOCS: &str = "https://github.com/parad0xe/arch-setup/blob/main/docs/manifest.md";

const MANIFEST: &str = r#"# An example module: one unit, with what a unit can declare. The format is
# docs/manifest.md of https://github.com/parad0xe/arch-setup. Rename the
# folder: the module takes its name; its hooks are in hooks.sh beside, its
# files under files/.

[module]
name = "Example"
about = "What the units of this module have in common"

[[unit]]
id = "example"
name = "An example unit"
about = "Installs a package, deploys a file and runs a hook. Replace it with your own units."
# when = { distro = "arch" }              # conditions on the machine
# requires = ["desktop"]                  # units it needs (of the public repository too)
packages = ["tree"]
# aur = ["an-aur-package"]
# services = [{ name = "a.service", now = true }]
# A copy by default; mode = "symlink" links to this repository instead, and
# backup = true keeps a different existing file as .bak
files = [{ source = "files/example.conf", target = ".config/example.conf" }]
inputs = [{ id = "greeting", prompt = "A greeting for the example hook", default = "hello" }]
hooks = ["say_hello"]

# A fragment adds to a unit of a repository read before this one (the public
# one, for a private repository), or replaces its configuration with
# override = "...": its files come from this module, its hooks from hooks.sh.
# [[unit]]
# extend = "desktop"
# files = [{ source = "files/hypr/local.lua", target = ".config/hypr/local.lua" }]
"#;

const HOOKS: &str = r#"#!/bin/bash
# The hooks of the example module: functions run by lib/hook.sh after the
# packages, services and files of a unit, with the answers in INPUT_<ID> and
# the variants in VARIANT_<ID>. A hook never asks a question, and changes
# nothing when it runs a second time.

say_hello() {
    log_info "$INPUT_GREETING from the example unit on $HOST_DISTRO"
}
"#;

const EXAMPLE_FILE: &str = "# Deployed into the home folder by the example unit\n";

const PROFILE: &str = r#"# An example profile: a ready-made selection. `extends` may name a profile
# of the public repository.
about = "The example unit"
units = ["example"]

[inputs]
"example.greeting" = "hello"
"#;

fn readme(public: bool) -> String {
    let use_it = if public {
        "Use it with `setup --repo <this folder>`; on a fresh machine, once\n\
         pushed: `curl -fsSL https://raw.githubusercontent.com/parad0xe/arch-setup/main/bootstrap.sh | SETUP_REPO=<owner>/<name> bash`.\n\
         `lib/` is the hook library of arch-setup; `lib/hook.sh` runs the hooks."
    } else {
        "Use it with `setup --private <this folder or its HTTPS URL>`: its\n\
         modules and profiles add up to the public repository's, after them."
    };
    format!(
        "# A setup repository\n\n\
         Modules, profiles and files for setup\n\
         (https://github.com/parad0xe/arch-setup); the format is\n\
         {DOCS}.\n\n\
         ```\n\
         modules/<module>/module.toml   the units of a module\n\
         modules/<module>/hooks.sh      their hooks (bash functions)\n\
         modules/<module>/files/        what its units deploy (the source of their files)\n\
         profiles/<name>.toml           ready-made selections\n\
         ```\n\n\
         {use_it}\n"
    )
}

/// Creates the repository, reads it back, and starts git in it.
pub fn new(config: &Config, console: &mut Console, dir: &Path, public: bool) -> Result<ExitCode> {
    if dir.exists() && dir.read_dir()?.next().is_some() {
        bail!("{}: not empty", dir.display());
    }
    for folder in ["modules/example/files", "profiles"] {
        fs::create_dir_all(dir.join(folder))
            .with_context(|| format!("creating {}", dir.join(folder).display()))?;
    }
    write(&dir.join("modules/example/module.toml"), MANIFEST)?;
    write(&dir.join("modules/example/hooks.sh"), HOOKS)?;
    write(
        &dir.join("modules/example/files/example.conf"),
        EXAMPLE_FILE,
    )?;
    write(&dir.join("profiles/example.toml"), PROFILE)?;
    write(&dir.join("README.md"), &readme(public))?;
    if public {
        copy_library(config.public_root()?, dir)?;
    }

    // Read back as the setup would
    let repository = Repository::open(dir)?;
    let declarations = repository.declarations()?;
    Registry::new(declarations, &host::probe_platform())?;
    Profiles::new(repository.profiles()?)?;

    let kind = if public { "public" } else { "private" };
    console.success(&format!(
        "Created a {kind} repository of modules in {}.",
        config.tilde(dir)
    ));
    if start_git(dir) {
        console.text("  git is started in it: add your remote and commit.");
    }
    console.text(&format!(
        "  Edit modules/example/module.toml and hooks.sh (the format: {DOCS})."
    ));
    if public {
        console.text(&format!(
            "  Then: {} --repo {}",
            config.program,
            config.tilde(dir)
        ));
    } else {
        console.text(&format!(
            "  Then: {} --private {}",
            config.program,
            config.tilde(dir)
        ));
    }
    Ok(ExitCode::SUCCESS)
}

fn write(path: &Path, text: &str) -> Result<()> {
    fs::write(path, text).with_context(|| format!("writing {}", path.display()))
}

/// The hook library of the public repository, so that the new one runs its
/// hooks on its own.
fn copy_library(public_root: &Path, dir: &Path) -> Result<()> {
    let source = public_root.join("lib");
    let target = dir.join("lib");
    fs::create_dir_all(&target).with_context(|| format!("creating {}", target.display()))?;
    let mut entries: Vec<_> = fs::read_dir(&source)
        .with_context(|| format!("reading {}", source.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|e| e == "sh"))
        .collect();
    entries.sort();
    if entries.is_empty() {
        bail!("{}: no hook library to copy", source.display());
    }
    for script in entries {
        let name = script.file_name().unwrap_or_default();
        fs::copy(&script, target.join(name))
            .with_context(|| format!("copying {}", script.display()))?;
    }
    Ok(())
}

/// `git init`, when git is there and the folder is not already in a
/// repository. Tells whether it happened.
fn start_git(dir: &Path) -> bool {
    let quiet = |command: &mut Command| {
        command
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok_and(|s| s.success())
    };
    if !quiet(Command::new("git").arg("--version")) {
        return false;
    }
    if quiet(
        Command::new("git")
            .arg("-C")
            .arg(dir)
            .args(["rev-parse", "--is-inside-work-tree"]),
    ) {
        return false;
    }
    quiet(Command::new("git").args(["init", "-q"]).arg(dir))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_templates_make_a_repository_the_model_accepts() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("mine");
        for folder in ["modules/example/files", "profiles"] {
            fs::create_dir_all(root.join(folder)).unwrap();
        }
        write(&root.join("modules/example/module.toml"), MANIFEST).unwrap();
        write(&root.join("modules/example/hooks.sh"), HOOKS).unwrap();
        write(
            &root.join("modules/example/files/example.conf"),
            EXAMPLE_FILE,
        )
        .unwrap();
        write(&root.join("profiles/example.toml"), PROFILE).unwrap();
        let repository = Repository::open(&root).unwrap();
        let declarations = repository.declarations().unwrap();
        assert_eq!(declarations.modules[0].units[0].hooks[0].run, "say_hello");
        let platform = model::Platform {
            distro: "arch".into(),
            arch: "x86_64".into(),
            ..Default::default()
        };
        let registry = Registry::new(declarations, &platform).unwrap();
        let profiles = Profiles::new(repository.profiles().unwrap()).unwrap();
        let resolved = profiles.resolve("example", &registry).unwrap();
        assert!(resolved.selection.contains("example") && resolved.warnings.is_empty());
        assert!(readme(true).contains("--repo") && readme(false).contains("--private"));
    }
}
