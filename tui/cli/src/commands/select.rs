//! The screens, then what the user decided: a run, a resume, a profile
//! saved, or a private repository added before coming back.

use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use journal::Run;
use model::{InputKind, Profile, Registry, Selection};
use screens::{Outcome, SelectContext};

use crate::commands::common::{self, Setup};
use crate::config::Config;
use crate::console::Console;
use crate::private;

pub fn select(config: Config, console: &mut Console) -> Result<ExitCode> {
    let mut private = private::initial(&config, console, None)?;
    loop {
        let setup = Setup::load(config.clone(), private.clone())?;
        check_config(&setup.registry, &config.config)?;
        let unfinished = setup.unfinished()?;
        let machine = host::probe_machine();
        let description = unfinished.as_ref().map(Run::describe);
        let context = SelectContext {
            registry: &setup.registry,
            profiles: &setup.profiles,
            machine: &machine,
            resumable: description.as_deref(),
            private: private.as_ref().map(|p| p.source.as_str()),
            ascii: config.ascii,
            dry_run: config.dry_run,
            files_only: config.files_only,
            config: &config.config,
        };
        match screens::select(&context)? {
            Outcome::Quit => {
                console.text("Setup cancelled.");
                return Ok(ExitCode::SUCCESS);
            }
            Outcome::Private(source) => match private::obtain(&config, console, &source) {
                Ok(added) => private = Some(added),
                Err(error) => {
                    console.error(&format!("{error:#}"));
                    console.pause("Enter goes back to the screens.")?;
                }
            },
            Outcome::Save {
                name,
                profile,
                selection,
            } => return save(&setup, console, &name, &profile, &selection),
            Outcome::Resume => {
                let run = unfinished.context("no run to resume")?;
                return common::resume(&setup, console, &run);
            }
            Outcome::Run { profile, selection } => {
                return common::start(&setup, console, &profile, &selection, unfinished);
            }
        }
    }
}

/// The units of --config exist and are offered.
fn check_config(registry: &Registry, units: &[String]) -> Result<()> {
    for id in units {
        let Some(unit) = registry.unit(id) else {
            bail!("unknown unit {id}: setup dump lists them");
        };
        if !unit.offered() {
            bail!(
                "unit {id} is not offered: it runs always, comes with its parent, or is not for this machine"
            );
        }
    }
    Ok(())
}

fn save(
    setup: &Setup,
    console: &mut Console,
    name: &str,
    started_from: &str,
    selection: &Selection,
) -> Result<ExitCode> {
    let profile = profile_of(&setup.registry, name, started_from, selection);
    let path = repo::write_profile(&setup.config.profiles_dir, &profile)?;
    console.success(&format!("Profile saved: {}", setup.config.tilde(&path)));
    console.text(&format!(
        "Run it with: {} profile {name}",
        setup.config.program
    ));
    Ok(ExitCode::SUCCESS)
}

/// The profile of a selection: the units picked, the variants, the answers
/// (the secrets left out).
fn profile_of(
    registry: &Registry,
    name: &str,
    started_from: &str,
    selection: &Selection,
) -> Profile {
    let not_secret = |unit: &str, input: &str| {
        registry
            .unit(unit)
            .and_then(|u| u.input(input))
            .is_some_and(|i| i.kind != InputKind::Secret)
    };
    Profile {
        name: name.to_string(),
        about: (started_from != "none")
            .then(|| format!("Saved from the screens, started from {started_from}")),
        extends: None,
        units: selection.units().map(str::to_string).collect(),
        exclude: Vec::new(),
        variants: selection
            .variants()
            .map(|(unit, variant, option)| (format!("{unit}.{variant}"), option.to_string()))
            .collect(),
        inputs: selection
            .inputs()
            .filter(|(unit, input, _)| not_secret(unit, input))
            .map(|(unit, input, value)| (format!("{unit}.{input}"), value.clone()))
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use model::{
        Declarations, FileEntry, Input, InputValue, Mode, ModuleDeclaration, Platform,
        UnitDeclaration, Variant,
    };
    use std::path::PathBuf;

    #[test]
    fn a_saved_profile_keeps_the_picks_and_leaves_the_secrets_out() {
        let mut git = UnitDeclaration {
            id: "git".into(),
            name: "Git".into(),
            ..Default::default()
        };
        git.inputs = vec![
            Input {
                id: "name".into(),
                prompt: "Name".into(),
                ..Default::default()
            },
            Input {
                id: "token".into(),
                prompt: "Token".into(),
                kind: InputKind::Secret,
                ..Default::default()
            },
            Input {
                id: "fido".into(),
                prompt: "FIDO".into(),
                kind: InputKind::Bool,
                ..Default::default()
            },
        ];
        git.variants = vec![Variant {
            id: "config".into(),
            name: "C".into(),
            options: vec!["a".into(), "b".into()],
            default: None,
        }];
        git.files = vec![FileEntry {
            source: "git/{config}".into(),
            target: ".gitconfig".into(),
            mode: Mode::Symlink,
            contents: false,
            backup: true,
            permissions: None,
        }];
        let registry = Registry::new(
            Declarations {
                modules: vec![ModuleDeclaration {
                    id: "settings".into(),
                    name: "S".into(),
                    about: None,
                    root: PathBuf::from("/r"),
                    units: vec![git],
                    fragments: Vec::new(),
                }],
            },
            &Platform {
                distro: "arch".into(),
                arch: "x86_64".into(),
                ..Default::default()
            },
        )
        .unwrap();
        let mut selection = Selection::new();
        selection.select("git");
        selection.set_variant("git", "config", "b");
        selection.set_input("git", "name", InputValue::Text("me".into()));
        selection.set_input("git", "token", InputValue::Text("s3cret".into()));
        selection.set_input("git", "fido", InputValue::Flag(true));

        let profile = profile_of(&registry, "mine", "full", &selection);
        assert_eq!(profile.units, ["git"]);
        assert_eq!(
            profile.variants.get("git.config").map(String::as_str),
            Some("b")
        );
        assert_eq!(
            profile.inputs.get("git.name"),
            Some(&InputValue::Text("me".into()))
        );
        assert_eq!(
            profile.inputs.get("git.fido"),
            Some(&InputValue::Flag(true))
        );
        assert!(
            !profile.inputs.contains_key("git.token"),
            "{:?}",
            profile.inputs
        );
        assert!(
            profile
                .about
                .as_deref()
                .unwrap_or_default()
                .contains("full")
        );
        assert!(
            profile_of(&registry, "mine", "none", &selection)
                .about
                .is_none()
        );
    }
}
