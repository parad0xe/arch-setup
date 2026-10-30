//! The last unfinished run, resumed where it stopped, with the private
//! repository it used.

use std::process::ExitCode;

use anyhow::Result;
use journal::RunStore;

use crate::commands::common::{self, Setup};
use crate::config::Config;
use crate::console::Console;
use crate::private;

pub fn resume(config: Config, console: &mut Console) -> Result<ExitCode> {
    let store = RunStore::new(&config.state_dir);
    let Some(run) = store.resumable()? else {
        console.info("Nothing to resume: the last run finished (logs shows it).");
        return Ok(ExitCode::SUCCESS);
    };
    let recorded = run.private();
    let private = private::initial(&config, console, recorded.as_deref())?;
    let setup = Setup::load(config, private)?;
    common::resume(&setup, console, &run)
}
