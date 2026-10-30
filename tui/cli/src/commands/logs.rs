//! The last run: its steps, their status and their logs. Needs no
//! repository.

use std::process::ExitCode;

use anyhow::Result;
use journal::RunStore;

use crate::config::Config;
use crate::console::Console;

pub fn logs(config: &Config, console: &mut Console) -> Result<ExitCode> {
    let store = RunStore::new(&config.state_dir);
    let Some(run) = store.latest()? else {
        console.text(&format!(
            "No run yet (runs are kept in {}).",
            config.tilde(&store.runs_dir())
        ));
        return Ok(ExitCode::SUCCESS);
    };
    console.blank();
    console.title(&format!("Last {}", run.describe()));
    console.text(&format!("Folder: {}", config.tilde(run.dir())));
    if let Some(private) = run.private() {
        console.text(&format!("Private repository: {private}"));
    }
    console.blank();
    let width = run
        .steps()
        .iter()
        .map(|s| s.chars().count())
        .max()
        .unwrap_or(0);
    for (i, unit) in run.steps().iter().enumerate() {
        let status = run.status(unit);
        let code = run
            .code(unit)
            .map(|c| format!(" ({c})"))
            .unwrap_or_default();
        let log = run.step_log(i + 1)?;
        console.text(&format!(
            "  {:>3}  {:<14} {:<width$}  steps/{}",
            i + 1,
            format!("{}{code}", status.as_str()),
            unit,
            log.file_name().unwrap_or_default().to_string_lossy()
        ));
    }
    console.blank();
    console.text(&format!(
        "The setup.log of the folder holds what the setup printed; the other runs are in {}.",
        config.tilde(&store.runs_dir())
    ));
    console.blank();
    Ok(ExitCode::SUCCESS)
}
