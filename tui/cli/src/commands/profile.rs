//! A profile run without the screens.

use std::process::ExitCode;

use anyhow::{Result, anyhow};
use model::ProfileError;

use crate::commands::common::{self, Setup};
use crate::config::Config;
use crate::console::Console;
use crate::private;

pub fn profile(config: Config, console: &mut Console, name: &str) -> Result<ExitCode> {
    let private = private::initial(&config, console, None)?;
    let setup = Setup::load(config, private)?;
    let resolved = setup
        .profiles
        .resolve(name, &setup.registry)
        .map_err(|error| match error {
            ProfileError::Unknown(_) => {
                let names: Vec<&str> = setup.profiles.names().collect();
                anyhow!(
                    "unknown profile {name} (the profiles: {})",
                    names.join(", ")
                )
            }
            other => anyhow!(other),
        })?;
    for warning in &resolved.warnings {
        console.warn(warning);
    }
    let unfinished = setup.unfinished()?;
    if let Some(run) = &unfinished {
        if console.can_prompt() {
            let question = format!("An earlier {} did not finish. Resume it?", run.describe());
            if console.confirm(&question, true)? {
                return common::resume(&setup, console, run);
            }
        }
    }
    common::start(&setup, console, name, &resolved.selection, unfinished)
}
