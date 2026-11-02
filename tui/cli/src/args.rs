//! The command line: a command and the options.

use std::path::PathBuf;

use clap::error::ErrorKind;
use clap::{CommandFactory, Parser, Subcommand};

/// The Arch setup from a terminal: pick a profile and the units to install,
/// answer the questions, then run the plan step by step, each step with its
/// log, resumable where it stopped.
#[derive(Debug, Parser, PartialEq, Eq)]
#[command(name = "setup", version, about, long_about = None)]
pub struct Args {
    #[command(subcommand)]
    pub command: Option<Command>,

    /// Show what would run, change nothing
    #[arg(short = 'n', long, global = true)]
    pub dry_run: bool,

    /// Deploy the files of the selected units (their variants) and run their
    /// hooks, nothing else: no packages, services nor checks
    #[arg(long, global = true)]
    pub files_only: bool,

    /// Redeploy the configs of this unit: the screens open on its variants,
    /// the unit selected, files only (repeat for several units)
    #[arg(long, global = true, value_name = "UNIT")]
    pub config: Vec<String>,

    /// Answer the questions with their default and skip the units that need
    /// the terminal (with profile or resume)
    #[arg(short = 'y', long, global = true)]
    pub yes: bool,

    /// A private repository read after the public one: an HTTPS URL (a
    /// token is asked) or a folder
    #[arg(long, global = true, value_name = "URL|DIR")]
    pub private: Option<String>,

    /// The setup repository (default: SETUP_DIR, or found from the current
    /// folder)
    #[arg(long, global = true, value_name = "DIR")]
    pub repo: Option<PathBuf>,

    /// Where the saved profiles are (default: ~/.local/share/arch-setup/profiles)
    #[arg(long, global = true, value_name = "DIR")]
    pub profiles: Option<PathBuf>,

    /// Plain symbols and borders (the Linux console)
    #[arg(long, global = true)]
    pub ascii: bool,

    /// What the setup has to say to Windows
    #[arg(long, global = true)]
    pub windows: bool,
}

#[derive(Debug, Subcommand, PartialEq, Eq)]
pub enum Command {
    /// The screens, then the run (the default)
    Select,
    /// Run a profile without the screens
    Profile {
        /// A profile of the repository, or a saved one
        name: String,
    },
    /// Resume the last run where it stopped
    Resume,
    /// Show the steps and the logs of the last run
    Logs,
    /// Print the platform, the units and the profiles as JSON
    Dump,
    /// Create a repository of modules: an example module, profile and
    /// README, private (read after this repository) unless --public
    New {
        /// An empty or missing folder
        dir: PathBuf,
        /// A repository standing alone: the hook library comes along
        #[arg(long)]
        public: bool,
    },
}

impl Args {
    /// The command, `select` when none is given.
    pub fn command(&self) -> &Command {
        self.command.as_ref().unwrap_or(&Command::Select)
    }
}

/// Parses the command line (the program name first); a mistake prints the
/// usage and exits with 2.
pub fn parse(argv: &[String]) -> Args {
    let args = Args::parse_from(argv);
    if let Err(message) = check(&args) {
        <Args as CommandFactory>::command()
            .error(ErrorKind::ArgumentConflict, message)
            .exit();
    }
    args
}

/// What does not go together.
fn check(args: &Args) -> Result<(), String> {
    match args.command() {
        Command::Resume if args.dry_run => {
            Err("resume cannot be a dry run: it would mark the steps done".to_string())
        }
        Command::Resume if args.files_only => Err(
            "resume runs the plan as recorded: --files-only goes with select or profile"
                .to_string(),
        ),
        Command::Select | Command::Logs | Command::Dump | Command::New { .. } if args.yes => {
            Err("--yes goes with profile <name> or resume".to_string())
        }
        Command::Profile { .. }
        | Command::Resume
        | Command::Logs
        | Command::Dump
        | Command::New { .. }
            if !args.config.is_empty() =>
        {
            Err("--config goes with the screens: setup --config <unit>".to_string())
        }
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_line(line: &str) -> Result<Args, clap::Error> {
        let argv: Vec<&str> = std::iter::once("setup")
            .chain(line.split_whitespace())
            .collect();
        Args::try_parse_from(argv)
    }

    #[test]
    fn commands_and_options_are_parsed() {
        let args = parse_line("profile demo -n -y --ascii --repo /r --profiles /p --private /usb")
            .unwrap();
        assert_eq!(
            args.command(),
            &Command::Profile {
                name: "demo".to_string()
            }
        );
        assert!(args.dry_run && args.yes && args.ascii);
        assert_eq!(args.repo.as_deref(), Some(std::path::Path::new("/r")));
        assert_eq!(args.profiles.as_deref(), Some(std::path::Path::new("/p")));
        assert_eq!(args.private.as_deref(), Some("/usb"));
        assert_eq!(parse_line("").unwrap().command(), &Command::Select);
        assert_eq!(parse_line("--dry-run").unwrap().command(), &Command::Select);
        assert_eq!(
            parse_line("resume --yes").unwrap().command(),
            &Command::Resume
        );
        assert_eq!(parse_line("logs").unwrap().command(), &Command::Logs);
        assert!(parse_line("--files-only").unwrap().files_only);
        assert!(parse_line("--windows").unwrap().windows);
        assert_eq!(
            parse_line("--config waybar --config git").unwrap().config,
            ["waybar", "git"]
        );
        assert_eq!(parse_line("dump").unwrap().command(), &Command::Dump);
        assert_eq!(
            parse_line("new /tmp/mine --public").unwrap().command(),
            &Command::New {
                dir: PathBuf::from("/tmp/mine"),
                public: true
            }
        );
    }

    #[test]
    fn what_does_not_go_together_is_refused() {
        assert!(check(&parse_line("resume --dry-run").unwrap()).is_err());
        assert!(check(&parse_line("resume --files-only").unwrap()).is_err());
        assert!(check(&parse_line("profile x --files-only").unwrap()).is_ok());
        assert!(check(&parse_line("profile x --config waybar").unwrap()).is_err());
        assert!(check(&parse_line("--config waybar --files-only").unwrap()).is_ok());
        assert!(check(&parse_line("--yes").unwrap()).is_err());
        assert!(check(&parse_line("logs -y").unwrap()).is_err());
        assert!(check(&parse_line("profile x -y -n").unwrap()).is_ok());
        assert!(parse_line("--bogus").is_err());
        assert!(parse_line("--repo").is_err());
        assert!(parse_line("profile").is_err(), "a profile needs a name");
        assert!(
            parse_line("new").is_err(),
            "a new repository needs a folder"
        );
        assert!(check(&parse_line("new /tmp/x -y").unwrap()).is_err());
    }
}
