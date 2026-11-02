//! setup: the Arch setup from a terminal. The arguments (`args`), the
//! environment and the folders (`config`), the console (`console`), the
//! commands (`commands`) and the private repository (`private`) are the
//! binary's; what the setup is, where it runs and how come from the crates
//! of the workspace.

mod app;
mod args;
mod commands;
mod config;
mod console;
mod private;

use std::process::ExitCode;

fn main() -> ExitCode {
    let environment = config::Environment::current();
    let args = args::parse(&environment.argv);
    app::run(&args, &environment).unwrap_or_else(|error| {
        eprintln!("{}: {error:#}", environment.program);
        ExitCode::FAILURE
    })
}
