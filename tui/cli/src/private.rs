//! The private repository: a second repository with the same layout, given
//! as a folder (used in place) or as an HTTPS URL, cloned with a token asked
//! on the terminal and handed to git alone. Its source is remembered for the
//! next launches.

use std::fs;
use std::io::{ErrorKind, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{Context, Result, bail};
use tempfile::TempPath;

use crate::config::Config;
use crate::console::Console;

/// A private repository in use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Private {
    /// The URL or the folder it was given as.
    pub source: String,
    pub root: PathBuf,
}

/// What a source names.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Source {
    Folder(PathBuf),
    Https(String),
    Ssh(String),
    Unknown,
}

fn classify(source: &str, home: &Path) -> Source {
    let text = source.trim();
    if text.starts_with("https://") {
        return Source::Https(text.to_string());
    }
    let scp_like = !text.contains("://")
        && text
            .split('/')
            .next()
            .is_some_and(|first| first.contains(':'));
    if text.starts_with("ssh://") || text.starts_with("git@") || scp_like {
        return Source::Ssh(text.to_string());
    }
    let path = match text.strip_prefix("~/") {
        Some(rest) => home.join(rest),
        None if text == "~" => home.to_path_buf(),
        None => PathBuf::from(text),
    };
    if path.is_dir() {
        Source::Folder(path)
    } else {
        Source::Unknown
    }
}

/// The private repository of this launch: the source preferred or asked for
/// on the command line, else the remembered one, refreshed quietly when a
/// token is not needed; none otherwise.
pub fn initial(
    config: &Config,
    console: &mut Console,
    preferred: Option<&str>,
) -> Result<Option<Private>> {
    if let Some(source) = preferred
        .map(str::to_string)
        .or_else(|| config.private.clone())
    {
        return obtain(config, console, &source).map(Some);
    }
    match remembered(config)? {
        Some(source) => Ok(quiet(config, console, &source)),
        None => Ok(None),
    }
}

/// Obtains a private repository from a source and remembers it.
pub fn obtain(config: &Config, console: &mut Console, source: &str) -> Result<Private> {
    let private = match classify(source, &config.home) {
        Source::Folder(root) => {
            check_layout(&root)?;
            Private {
                source: source.trim().to_string(),
                root: fs::canonicalize(&root)
                    .with_context(|| format!("resolving {}", root.display()))?,
            }
        }
        Source::Https(url) => {
            clone_or_pull(config, console, &url)?;
            check_layout(&config.private_dir)?;
            Private {
                source: url,
                root: config.private_dir.clone(),
            }
        }
        Source::Ssh(_) => bail!(
            "an SSH URL needs a key this machine may not have yet: use an HTTPS URL (a token is asked) or a folder"
        ),
        Source::Unknown => bail!("{source}: not a folder nor an HTTPS URL"),
    };
    remember(config, &private.source)?;
    Ok(private)
}

/// The remembered repository as it is: a folder still there, or the clone,
/// pulled when no token is needed. Gone otherwise.
fn quiet(config: &Config, console: &mut Console, source: &str) -> Option<Private> {
    match classify(source, &config.home) {
        Source::Folder(root) if root.join("modules").is_dir() => Some(Private {
            source: source.to_string(),
            root,
        }),
        Source::Https(url) if config.private_dir.join(".git").is_dir() => {
            if pull(config, None).is_err() {
                console.warn(&format!(
                    "The private repository was not refreshed (a token is needed): pass --private {url} to refresh it."
                ));
            }
            Some(Private {
                source: url,
                root: config.private_dir.clone(),
            })
        }
        _ => {
            console.warn(&format!(
                "The private repository {source} is not there any more: pass --private to add one."
            ));
            None
        }
    }
}

fn remembered(config: &Config) -> Result<Option<String>> {
    match fs::read_to_string(&config.private_source) {
        Ok(text) => Ok(Some(text.trim().to_string()).filter(|s| !s.is_empty())),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(None),
        Err(error) => {
            Err(error).with_context(|| format!("reading {}", config.private_source.display()))
        }
    }
}

fn remember(config: &Config, source: &str) -> Result<()> {
    if let Some(parent) = config.private_source.parent() {
        fs::create_dir_all(parent).with_context(|| format!("creating {}", parent.display()))?;
    }
    fs::write(&config.private_source, format!("{source}\n"))
        .with_context(|| format!("writing {}", config.private_source.display()))
}

fn check_layout(root: &Path) -> Result<()> {
    if !root.join("modules").is_dir() {
        bail!(
            "{}: no modules folder, not a setup repository",
            root.display()
        );
    }
    Ok(())
}

/// Clones the URL into the private folder, or pulls when it is already
/// there, with a token asked on the terminal.
fn clone_or_pull(config: &Config, console: &mut Console, url: &str) -> Result<()> {
    let dir = &config.private_dir;
    let existing = dir.join(".git").is_dir();
    if existing {
        let remote = git_output(dir, &["remote", "get-url", "origin"])?;
        if remote.trim() != url {
            bail!(
                "{} already holds a clone of {}: remove it, or pass that URL",
                dir.display(),
                remote.trim()
            );
        }
    } else if dir.exists() {
        bail!(
            "{} exists and is not a clone: remove it first",
            dir.display()
        );
    }
    let host = url.split('/').nth(2).unwrap_or(url);
    console.info(&format!(
        "The private repository needs a token for {host}: it is handed to git alone, nothing is written."
    ));
    let user = console.ask(
        &format!("User name for {host} (GitHub accepts any with a token)"),
        Some("git"),
    )?;
    let token = console.ask_secret(&format!("Token for {host}"))?;
    if token.is_empty() {
        bail!("no token given");
    }
    let credentials = Credentials {
        user,
        token,
        askpass: Askpass::new(&config.state_dir)?,
    };
    if existing {
        console.info("Refreshing the private repository.");
        pull(config, Some(&credentials))
    } else {
        console.info(&format!("Cloning {url} into {}.", config.tilde(dir)));
        if let Some(parent) = dir.parent() {
            fs::create_dir_all(parent).with_context(|| format!("creating {}", parent.display()))?;
        }
        git(
            None,
            &["clone", "--quiet", url, &dir.to_string_lossy()],
            Some(&credentials),
        )
    }
}

fn pull(config: &Config, credentials: Option<&Credentials>) -> Result<()> {
    git(
        Some(&config.private_dir),
        &["pull", "--quiet", "--ff-only"],
        credentials,
    )
}

/// Runs git without ever prompting on the terminal: the credentials, when
/// given, come through GIT_ASKPASS.
fn git(dir: Option<&Path>, args: &[&str], credentials: Option<&Credentials>) -> Result<()> {
    let mut command = Command::new("git");
    if let Some(dir) = dir {
        command.arg("-C").arg(dir);
    }
    command
        .args(args)
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped());
    if let Some(credentials) = credentials {
        command
            .env("GIT_ASKPASS", credentials.askpass.path())
            .env(ASKPASS_USER, &credentials.user)
            .env(ASKPASS_TOKEN, &credentials.token);
    }
    let output = command.output().context("running git (is it installed?)")?;
    if output.status.success() {
        Ok(())
    } else {
        bail!(
            "git {}: {}",
            args.first().unwrap_or(&""),
            String::from_utf8_lossy(&output.stderr).trim()
        )
    }
}

fn git_output(dir: &Path, args: &[&str]) -> Result<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdin(Stdio::null())
        .output()
        .context("running git (is it installed?)")?;
    if !output.status.success() {
        bail!(
            "git {}: {}",
            args.first().unwrap_or(&""),
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// The environment the askpass script answers from.
const ASKPASS_USER: &str = "SETUP_GIT_USER";
const ASKPASS_TOKEN: &str = "SETUP_GIT_TOKEN";

struct Credentials {
    user: String,
    token: String,
    askpass: Askpass,
}

/// The script git asks the credentials from: written and closed (git runs
/// it), removed when dropped.
struct Askpass(TempPath);

impl Askpass {
    fn new(dir: &Path) -> Result<Askpass> {
        fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
        let mut file = tempfile::Builder::new()
            .prefix("askpass-")
            .suffix(".sh")
            .permissions(fs::Permissions::from_mode(0o700))
            .tempfile_in(dir)
            .with_context(|| format!("creating the askpass script in {}", dir.display()))?;
        file.write_all(Askpass::script().as_bytes())
            .context("writing the askpass script")?;
        Ok(Askpass(file.into_temp_path()))
    }

    /// Answers git's prompts: the user name, then the token as the password.
    fn script() -> String {
        format!(
            "#!/bin/sh\ncase \"$1\" in\n    *sername*) printf '%s\\n' \"${ASKPASS_USER}\" ;;\n    *) printf '%s\\n' \"${ASKPASS_TOKEN}\" ;;\nesac\n"
        )
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sources_are_told_apart() {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path().join("home");
        fs::create_dir_all(home.join("usb")).unwrap();
        assert_eq!(
            classify("https://github.com/me/private.git", &home),
            Source::Https("https://github.com/me/private.git".into())
        );
        assert_eq!(
            classify(" https://x/y ", &home),
            Source::Https("https://x/y".into())
        );
        assert!(matches!(
            classify("git@github.com:me/private.git", &home),
            Source::Ssh(_)
        ));
        assert!(matches!(
            classify("ssh://git@host/me/private.git", &home),
            Source::Ssh(_)
        ));
        assert!(matches!(
            classify("host:me/private.git", &home),
            Source::Ssh(_)
        ));
        assert_eq!(classify("~/usb", &home), Source::Folder(home.join("usb")));
        assert_eq!(
            classify(home.join("usb").to_str().unwrap(), &home),
            Source::Folder(home.join("usb"))
        );
        assert_eq!(classify("/nonexistent/folder", &home), Source::Unknown);
        assert_eq!(classify("http://insecure/repo", &home), Source::Unknown);
    }

    #[test]
    fn the_askpass_script_answers_from_the_environment() {
        let dir = tempfile::tempdir().unwrap();
        let askpass = Askpass::new(&dir.path().join("state")).unwrap();
        let path = askpass.path().to_path_buf();
        let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o700);
        let answer = |prompt: &str| {
            let output = Command::new(&path)
                .arg(prompt)
                .env(ASKPASS_USER, "me")
                .env(ASKPASS_TOKEN, "s3cret")
                .output()
                .unwrap();
            String::from_utf8_lossy(&output.stdout).into_owned()
        };
        assert_eq!(answer("Username for 'https://github.com': "), "me\n");
        assert_eq!(answer("Password for 'https://me@github.com': "), "s3cret\n");
        drop(askpass);
        assert!(!path.exists(), "the script is removed");
    }
}
