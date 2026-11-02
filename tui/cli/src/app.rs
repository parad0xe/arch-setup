//! What the binary does once the arguments are parsed: the configuration,
//! the console, then the command.

use std::process::ExitCode;

use anyhow::Result;

use crate::args::{Args, Command};
use crate::commands;
use crate::config::{Config, Environment};
use crate::console::Console;

pub fn run(args: &Args, environment: &Environment) -> Result<ExitCode> {
    let config = Config::resolve(args, environment);
    let mut console = Console::new(&config);
    if args.windows {
        return Ok(commands::windows(&mut console, config.ascii));
    }
    match args.command() {
        Command::Select => commands::select(config, &mut console),
        Command::Profile { name } => commands::profile(config, &mut console, name),
        Command::Resume => commands::resume(config, &mut console),
        Command::Logs => commands::logs(&config, &mut console),
        Command::Dump => commands::dump(config, &mut console),
        Command::New { dir, public } => commands::new(&config, &mut console, dir, *public),
    }
}
