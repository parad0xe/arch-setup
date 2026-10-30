//! The programs the runner calls, and the commands it builds for the
//! packages and services of a distribution.

use std::process::Command;

/// The programs, by name on the PATH or by path. The tests point them at
/// fakes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Commands {
    pub sudo: String,
    pub bash: String,
    pub pacman: String,
    pub yay: String,
    pub apt_get: String,
    pub systemctl: String,
}

impl Default for Commands {
    fn default() -> Commands {
        Commands {
            sudo: "sudo".into(),
            bash: "bash".into(),
            pacman: "pacman".into(),
            yay: "yay".into(),
            apt_get: "apt-get".into(),
            systemctl: "systemctl".into(),
        }
    }
}

/// The package tools that must not be killed mid-package.
pub(crate) const PACKAGE_TOOLS: &[&str] = &[
    "pacman",
    "yay",
    "makepkg",
    "apt-get",
    "apt",
    "dpkg",
    "mkinitcpio",
    "dkms",
];

impl Commands {
    fn sudo(&self, program: &str) -> Command {
        let mut command = Command::new(&self.sudo);
        command.arg(program);
        command
    }

    /// Installs packages with the package manager of the distribution: the
    /// ones installed are left alone, conflicts go to the declared package.
    /// None for a distribution without one.
    pub(crate) fn install(&self, distro: &str, packages: &[String]) -> Option<Command> {
        let mut command = match distro {
            "arch" => {
                let mut c = self.sudo(&self.pacman);
                c.args(["-S", "--needed", "--noconfirm", "--ask=4"]);
                c
            }
            "ubuntu" => {
                let mut c = self.sudo(&self.apt_get);
                c.args(["install", "-y", "--no-install-recommends"]);
                c.env("DEBIAN_FRONTEND", "noninteractive");
                c
            }
            _ => return None,
        };
        command.args(packages);
        Some(command)
    }

    /// Installs AUR packages with yay, as the user. None outside Arch Linux.
    pub(crate) fn install_aur(&self, distro: &str, packages: &[String]) -> Option<Command> {
        if distro != "arch" {
            return None;
        }
        let mut command = Command::new(&self.yay);
        command.args(["-S", "--needed", "--noconfirm"]);
        command.args(packages);
        Some(command)
    }

    /// Enables a service, started as well with `now`, replacing a service
    /// of the same role with `force`.
    pub(crate) fn enable(&self, service: &model::Service) -> Command {
        let mut command = self.sudo(&self.systemctl);
        command.arg("enable");
        if service.now {
            command.arg("--now");
        }
        if service.force {
            command.arg("-f");
        }
        command.arg(&service.name);
        command
    }

    /// Runs a hook: `lib/hook.sh <module script> <function>`.
    pub(crate) fn hook(
        &self,
        hook_script: &std::path::Path,
        module_script: &std::path::Path,
        function: &str,
    ) -> Command {
        let mut command = Command::new(&self.bash);
        command.arg(hook_script).arg(module_script).arg(function);
        command
    }
}

/// A command as one line, for the logs.
pub(crate) fn describe(command: &Command) -> String {
    let mut words = vec![command.get_program().to_string_lossy().into_owned()];
    words.extend(command.get_args().map(|a| a.to_string_lossy().into_owned()));
    words.join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn commands_follow_the_distribution() {
        let commands = Commands::default();
        let pkgs = vec!["git".to_string(), "curl".to_string()];
        assert_eq!(
            describe(&commands.install("arch", &pkgs).unwrap()),
            "sudo pacman -S --needed --noconfirm --ask=4 git curl"
        );
        assert_eq!(
            describe(&commands.install("ubuntu", &pkgs).unwrap()),
            "sudo apt-get install -y --no-install-recommends git curl"
        );
        assert!(commands.install("fedora", &pkgs).is_none());
        assert_eq!(
            describe(&commands.install_aur("arch", &pkgs).unwrap()),
            "yay -S --needed --noconfirm git curl"
        );
        assert!(commands.install_aur("ubuntu", &pkgs).is_none());
        let service = model::Service {
            name: "sddm".into(),
            now: true,
            force: true,
        };
        assert_eq!(
            describe(&commands.enable(&service)),
            "sudo systemctl enable --now -f sddm"
        );
    }
}
