//! Whether the setup can run on this machine: the problems, each with how to
//! fix it, and the actions the user may take. Nothing is printed or asked
//! here: the binary decides and displays.

use std::path::{Path, PathBuf};

use model::Platform;

use crate::probe::{installed, succeeds};

pub const DEFAULT_PACMAN_LOCK: &str = "/var/lib/pacman/db.lck";

/// Where the network check goes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Network {
    pub url: String,
    pub host: String,
}

impl Default for Network {
    fn default() -> Network {
        Network {
            url: "https://archlinux.org/".to_string(),
            host: "archlinux.org".to_string(),
        }
    }
}

/// What the checks need to know.
#[derive(Debug, Clone)]
pub struct CheckContext<'a> {
    pub platform: &'a Platform,
    /// The distributions the manifests support.
    pub distributions: &'a [&'a str],
    /// A real run: the problems block, sudo is needed now.
    pub strict: bool,
    /// The questions are answered with their default (--yes).
    pub assume_yes: bool,
    /// A terminal is there to ask questions and type the sudo password.
    pub terminal: bool,
    pub pacman_lock: PathBuf,
    pub network: Network,
}

/// Something that prevents the run, and what to do about it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Problem {
    pub what: String,
    pub fix: String,
}

/// Something the user may do now.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// sudo needs the password: `authenticate` asks for it.
    AskSudoPassword,
    /// A pacman lock remains from an interrupted run: `remove_pacman_lock`
    /// removes it; `declined` is the problem otherwise.
    RemovePacmanLock { path: PathBuf, declined: Problem },
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CheckReport {
    pub problems: Vec<Problem>,
    /// Worth saying, not blocking.
    pub notes: Vec<String>,
    pub actions: Vec<Action>,
}

/// Runs the checks.
pub fn check(context: &CheckContext) -> CheckReport {
    let mut report = CheckReport::default();
    check_distribution(context, &mut report);
    check_architecture(context, &mut report);
    check_user(&mut report);
    check_terminal(context, &mut report);
    check_sudo(context, &mut report);
    check_network(context, &mut report);
    if context.platform.distro == "arch" {
        check_pacman_lock(&context.pacman_lock, context.strict, &mut report);
    }
    report
}

fn problem(report: &mut CheckReport, what: &str, fix: &str) {
    report.problems.push(Problem {
        what: what.to_string(),
        fix: fix.to_string(),
    });
}

fn check_distribution(context: &CheckContext, report: &mut CheckReport) {
    if !context
        .distributions
        .contains(&context.platform.distro.as_str())
    {
        let found = if context.platform.distro.is_empty() {
            "an unknown distribution"
        } else {
            &context.platform.distro
        };
        problem(
            report,
            &format!("This is {found}."),
            &format!("The setup runs on {}.", context.distributions.join(", ")),
        );
    }
}

fn check_architecture(context: &CheckContext, report: &mut CheckReport) {
    if !["x86_64", "aarch64"].contains(&context.platform.arch.as_str()) {
        problem(
            report,
            &format!("Unsupported architecture {}.", context.platform.arch),
            "The setup runs on x86_64 and aarch64.",
        );
    }
}

/// Not root: the configs go into the home of the user running the setup.
fn check_user(report: &mut CheckReport) {
    if nix::unistd::geteuid().is_root() {
        problem(
            report,
            "Running as root.",
            "Run the setup as your user: it deploys the configs into your home and uses sudo for the system steps.",
        );
    }
}

fn check_terminal(context: &CheckContext, report: &mut CheckReport) {
    if !context.terminal && !context.assume_yes {
        problem(
            report,
            "No terminal to ask questions on.",
            "Run the setup from a terminal, or pass --yes with a profile (-p <name> --yes).",
        );
    }
}

fn check_sudo(context: &CheckContext, report: &mut CheckReport) {
    if !installed("sudo") {
        problem(
            report,
            "sudo is not installed.",
            "As root: pacman -S sudo; usermod -aG wheel $USER; then allow the wheel group with: echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel; and log in again.",
        );
        return;
    }
    if succeeds("sudo", &["-n", "true"]) {
        return;
    }
    if !context.strict {
        report
            .notes
            .push("sudo will ask for your password when the setup runs.".to_string());
    } else if !context.terminal {
        problem(
            report,
            "sudo needs your password and there is no terminal to ask for it.",
            "Run 'sudo -v' first, or run the setup from a terminal.",
        );
    } else {
        report.actions.push(Action::AskSudoPassword);
    }
}

fn check_network(context: &CheckContext, report: &mut CheckReport) {
    let reachable = succeeds(
        "curl",
        &[
            "-fsS",
            "--max-time",
            "8",
            "-o",
            "/dev/null",
            &context.network.url,
        ],
    ) || succeeds("ping", &["-c", "1", "-W", "3", &context.network.host]);
    if !reachable {
        problem(
            report,
            "No network access.",
            "Connect first (nmcli device wifi connect <SSID> --ask, or iwctl), then run the setup again.",
        );
    }
}

/// No pacman running, no lock left by an interrupted one.
fn check_pacman_lock(lock: &Path, strict: bool, report: &mut CheckReport) {
    if !lock.exists() {
        return;
    }
    if succeeds("pgrep", &["-x", "pacman"]) {
        problem(
            report,
            "Another pacman is running.",
            "Wait for it to finish, then run the setup again.",
        );
        return;
    }
    let declined = Problem {
        what: "A pacman lock remains from an interrupted run.".to_string(),
        fix: format!(
            "When no pacman runs, remove it with: sudo rm {}",
            lock.display()
        ),
    };
    if strict {
        report.actions.push(Action::RemovePacmanLock {
            path: lock.to_path_buf(),
            declined,
        });
    } else {
        report.problems.push(declined);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn platform() -> Platform {
        Platform {
            distro: "arch".into(),
            arch: "x86_64".into(),
            ..Default::default()
        }
    }

    fn context<'a>(platform: &'a Platform, lock: &Path) -> CheckContext<'a> {
        CheckContext {
            platform,
            distributions: &["arch"],
            strict: true,
            assume_yes: false,
            terminal: true,
            pacman_lock: lock.to_path_buf(),
            network: Network::default(),
        }
    }

    #[test]
    fn distribution_architecture_and_terminal_are_checked() {
        let lock = Path::new("/nonexistent/db.lck");
        let other = Platform {
            distro: "fedora".into(),
            arch: "riscv64".into(),
            ..Default::default()
        };
        let report = check(&CheckContext {
            assume_yes: false,
            terminal: false,
            ..context(&other, lock)
        });
        let whats: Vec<&str> = report.problems.iter().map(|p| p.what.as_str()).collect();
        assert!(whats.contains(&"This is fedora."), "{whats:?}");
        assert!(
            whats.contains(&"Unsupported architecture riscv64."),
            "{whats:?}"
        );
        assert!(
            whats.contains(&"No terminal to ask questions on."),
            "{whats:?}"
        );

        let report = check(&CheckContext {
            assume_yes: true,
            terminal: false,
            strict: false,
            ..context(&platform(), lock)
        });
        assert!(
            !report
                .problems
                .iter()
                .any(|p| p.what.starts_with("No terminal")),
            "--yes needs no terminal"
        );
    }

    #[test]
    fn a_stale_lock_is_an_action_in_a_real_run_and_a_problem_otherwise() {
        let dir = std::env::temp_dir().join(format!("host-checks-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let lock = dir.join("db.lck");
        std::fs::write(&lock, "").unwrap();
        let platform = platform();
        let strict = check(&context(&platform, &lock));
        assert!(
            strict
                .actions
                .iter()
                .any(|a| matches!(a, Action::RemovePacmanLock { path, .. } if *path == lock)),
            "{strict:?}"
        );
        let dry = check(&CheckContext {
            strict: false,
            ..context(&platform, &lock)
        });
        assert!(
            dry.problems
                .iter()
                .any(|p| p.what.starts_with("A pacman lock remains")),
            "{dry:?}"
        );
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
