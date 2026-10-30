//! The environment the binary reads (nowhere else), and the configuration
//! of a launch: the folders and the switches, from the arguments and the
//! environment.

use std::fs::OpenOptions;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow};

use crate::args::Args;

/// The terminal the questions are asked on.
pub const TTY: &str = "/dev/tty";

/// What the binary reads from its environment.
#[derive(Debug, Clone)]
pub struct Environment {
    /// The command line, the program first.
    pub argv: Vec<String>,
    /// The program name, for the messages.
    pub program: String,
    pub home: PathBuf,
    pub current_dir: PathBuf,
    /// `SETUP_DIR`: the repository.
    pub setup_dir: Option<PathBuf>,
    /// `SETUP_STATE_DIR`: the runs.
    pub state_dir: Option<PathBuf>,
    pub xdg_state_home: Option<PathBuf>,
    pub xdg_data_home: Option<PathBuf>,
    pub term: String,
    /// `LC_ALL`, `LC_CTYPE` or `LANG`, the first set.
    pub locale: String,
    /// `NO_COLOR` is set.
    pub no_color: bool,
    /// `SETUP_NO_TTY` is set: no question is asked.
    pub no_tty: bool,
    pub stdout_terminal: bool,
    /// `/dev/tty` opens.
    pub tty_opens: bool,
    /// `PACMAN_LOCK`: another lock file, for the tests.
    pub pacman_lock: Option<PathBuf>,
}

impl Environment {
    pub fn current() -> Environment {
        let argv: Vec<String> = std::env::args().collect();
        let program = argv
            .first()
            .and_then(|p| Path::new(p).file_name())
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| "setup".to_string());
        Environment {
            program,
            argv,
            home: path_var("HOME").unwrap_or_else(|| PathBuf::from("/")),
            current_dir: std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/")),
            setup_dir: path_var("SETUP_DIR"),
            state_dir: path_var("SETUP_STATE_DIR"),
            xdg_state_home: path_var("XDG_STATE_HOME"),
            xdg_data_home: path_var("XDG_DATA_HOME"),
            term: std::env::var("TERM").unwrap_or_default(),
            locale: ["LC_ALL", "LC_CTYPE", "LANG"]
                .iter()
                .filter_map(|v| std::env::var(v).ok())
                .find(|v| !v.is_empty())
                .unwrap_or_default(),
            no_color: std::env::var_os("NO_COLOR").is_some(),
            no_tty: std::env::var_os("SETUP_NO_TTY").is_some(),
            stdout_terminal: std::io::stdout().is_terminal(),
            tty_opens: OpenOptions::new().read(true).write(true).open(TTY).is_ok(),
            pacman_lock: path_var("PACMAN_LOCK"),
        }
    }
}

fn path_var(name: &str) -> Option<PathBuf> {
    std::env::var_os(name)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
}

/// A launch: where things are and how to behave.
#[derive(Debug, Clone)]
pub struct Config {
    /// The public repository, when one was found.
    public_root: Option<PathBuf>,
    /// Where the repository was looked for, for the message.
    looked_from: PathBuf,
    /// The runs and the link to the latest one.
    pub state_dir: PathBuf,
    /// The profiles the user saves.
    pub profiles_dir: PathBuf,
    /// Where a private repository given by URL is cloned.
    pub private_dir: PathBuf,
    /// The file remembering the source of the private repository.
    pub private_source: PathBuf,
    /// The private repository asked for on the command line.
    pub private: Option<String>,
    pub home: PathBuf,
    pub dry_run: bool,
    /// Only the files and the hooks of the units: no packages, services nor
    /// checks.
    pub files_only: bool,
    /// Units selected from the start, the screens opening on their variants.
    pub config: Vec<String>,
    pub assume_yes: bool,
    /// Plain symbols and borders.
    pub ascii: bool,
    /// Colors on stdout.
    pub color: bool,
    /// stdout is a terminal: a status line can be rewritten.
    pub stdout_terminal: bool,
    /// A terminal is there for the questions and the sudo password.
    pub terminal: bool,
    pub pacman_lock: PathBuf,
    /// The arguments, for the record of a run.
    pub argv: String,
    pub program: String,
}

impl Config {
    pub fn resolve(args: &Args, env: &Environment) -> Config {
        let data = env
            .xdg_data_home
            .clone()
            .unwrap_or_else(|| env.home.join(".local/share"))
            .join("arch-setup");
        let state_dir = env.state_dir.clone().unwrap_or_else(|| {
            env.xdg_state_home
                .clone()
                .unwrap_or_else(|| env.home.join(".local/state"))
                .join("arch-setup")
        });
        Config {
            public_root: find_repository(args.repo.as_deref(), env),
            looked_from: env.current_dir.clone(),
            state_dir,
            profiles_dir: args
                .profiles
                .clone()
                .unwrap_or_else(|| data.join("profiles")),
            private_dir: data.join("private"),
            private_source: data.join("private.source"),
            private: args.private.clone(),
            home: env.home.clone(),
            dry_run: args.dry_run,
            // --config redeploys configs: the files alone
            files_only: args.files_only || !args.config.is_empty(),
            config: args.config.clone(),
            assume_yes: args.yes,
            ascii: args.ascii || ascii_terminal(env),
            color: env.stdout_terminal
                && !env.no_color
                && !env.term.is_empty()
                && env.term != "dumb",
            stdout_terminal: env.stdout_terminal,
            terminal: !env.no_tty && env.tty_opens,
            pacman_lock: env
                .pacman_lock
                .clone()
                .unwrap_or_else(|| PathBuf::from(host::DEFAULT_PACMAN_LOCK)),
            argv: env
                .argv
                .iter()
                .skip(1)
                .cloned()
                .collect::<Vec<_>>()
                .join(" "),
            program: env.program.clone(),
        }
    }

    /// The public repository; an error says where it was looked for.
    pub fn public_root(&self) -> Result<&Path> {
        self.public_root.as_deref().ok_or_else(|| {
            anyhow!(
                "no setup repository found from {}: pass --repo <dir> or set SETUP_DIR",
                self.looked_from.display()
            )
        })
    }

    /// A path with the home folder shortened to ~, for the messages.
    pub fn tilde(&self, path: &Path) -> String {
        tilde(path, &self.home)
    }
}

/// The repository: the given one, `SETUP_DIR`, or the first folder up from
/// the current one holding `modules/` and `lib/hook.sh`. Absolute.
fn find_repository(given: Option<&Path>, env: &Environment) -> Option<PathBuf> {
    if let Some(dir) = given.or(env.setup_dir.as_deref()) {
        return std::fs::canonicalize(dir).ok();
    }
    let mut dir = env.current_dir.clone();
    loop {
        if is_repository(&dir) {
            return std::fs::canonicalize(&dir).ok();
        }
        if !dir.pop() {
            return None;
        }
    }
}

fn is_repository(dir: &Path) -> bool {
    dir.join("modules").is_dir() && dir.join("lib/hook.sh").is_file()
}

/// The terminal lacks the Unicode symbols: the Linux console, or a locale
/// that is not UTF-8.
fn ascii_terminal(env: &Environment) -> bool {
    let locale = env.locale.to_uppercase();
    env.term == "linux" || !(locale.contains("UTF-8") || locale.contains("UTF8"))
}

pub fn tilde(path: &Path, home: &Path) -> String {
    match path.strip_prefix(home) {
        Ok(rest) if home != Path::new("/") => format!("~/{}", rest.display()),
        _ => path.display().to_string(),
    }
}

/// Opens the terminal for a question, whatever stdin and stdout are.
pub fn open_tty() -> Result<std::fs::File> {
    OpenOptions::new()
        .read(true)
        .write(true)
        .open(TTY)
        .with_context(|| format!("opening {TTY}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    fn environment(current_dir: &Path, home: &Path) -> Environment {
        Environment {
            argv: vec!["setup".into(), "profile".into(), "x".into()],
            program: "setup".into(),
            home: home.to_path_buf(),
            current_dir: current_dir.to_path_buf(),
            setup_dir: None,
            state_dir: None,
            xdg_state_home: None,
            xdg_data_home: None,
            term: "xterm-256color".into(),
            locale: "en_US.UTF-8".into(),
            no_color: false,
            no_tty: false,
            stdout_terminal: true,
            tty_opens: true,
            pacman_lock: None,
        }
    }

    #[test]
    fn the_repository_is_found_up_from_the_current_folder() {
        let dir = tempfile::tempdir().unwrap();
        let repo = dir.path().join("repo");
        std::fs::create_dir_all(repo.join("modules")).unwrap();
        std::fs::create_dir_all(repo.join("lib")).unwrap();
        std::fs::write(repo.join("lib/hook.sh"), "").unwrap();
        std::fs::create_dir_all(repo.join("tui/cli")).unwrap();
        let home = dir.path().join("home");
        let args = Args::parse_from(["setup", "profile", "x"]);
        let configured = Args::parse_from(["setup", "--config", "waybar"]);
        assert!(
            Config::resolve(&configured, &environment(&repo, &home)).files_only,
            "--config means the files alone"
        );

        let env = environment(&repo.join("tui/cli"), &home);
        let config = Config::resolve(&args, &env);
        assert_eq!(
            config.public_root().unwrap(),
            std::fs::canonicalize(&repo).unwrap()
        );
        assert_eq!(config.state_dir, home.join(".local/state/arch-setup"));
        assert_eq!(
            config.profiles_dir,
            home.join(".local/share/arch-setup/profiles")
        );
        assert_eq!(
            config.private_dir,
            home.join(".local/share/arch-setup/private")
        );
        assert_eq!(config.argv, "profile x");
        assert!(config.color && config.terminal && !config.ascii);
        assert_eq!(config.tilde(&home.join("x/y")), "~/x/y");

        let elsewhere = environment(dir.path(), &home);
        let error = Config::resolve(&args, &elsewhere)
            .public_root()
            .unwrap_err()
            .to_string();
        assert!(error.contains("pass --repo"), "{error}");

        // SETUP_DIR, the state folder, --repo and --profiles win
        let mut env = environment(dir.path(), &home);
        env.setup_dir = Some(repo.clone());
        env.state_dir = Some(dir.path().join("state"));
        assert_eq!(
            Config::resolve(&args, &env).public_root().unwrap(),
            std::fs::canonicalize(&repo).unwrap()
        );
        assert_eq!(
            Config::resolve(&args, &env).state_dir,
            dir.path().join("state")
        );
        let args = Args::parse_from([
            "setup",
            "--repo",
            repo.to_str().unwrap(),
            "--profiles",
            "/p",
        ]);
        let config = Config::resolve(&args, &elsewhere);
        assert_eq!(
            config.public_root().unwrap(),
            std::fs::canonicalize(&repo).unwrap()
        );
        assert_eq!(config.profiles_dir, Path::new("/p"));
    }

    #[test]
    fn the_console_and_the_locale_decide_the_symbols_and_the_colors() {
        let dir = tempfile::tempdir().unwrap();
        let args = Args::parse_from(["setup"]);
        let mut env = environment(dir.path(), dir.path());
        env.term = "linux".into();
        assert!(Config::resolve(&args, &env).ascii);
        env.term = "xterm".into();
        env.locale = "C".into();
        assert!(Config::resolve(&args, &env).ascii);
        env.locale = "fr_FR.utf8".into();
        env.no_color = true;
        let config = Config::resolve(&args, &env);
        assert!(!config.ascii && !config.color);
        env.no_color = false;
        env.stdout_terminal = false;
        env.no_tty = true;
        let config = Config::resolve(&args, &env);
        assert!(!config.color && !config.terminal && !config.stdout_terminal);
    }
}
