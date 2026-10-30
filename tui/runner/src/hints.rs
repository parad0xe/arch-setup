//! The probable cause of a failed step, read from the end of its log.

use regex_lite::Regex;

/// What a failure looks like in a log, and what to do about it.
const CAUSES: &[(&str, &str)] = &[
    (
        "could not resolve host|failure in name resolution|network is unreachable|failed retrieving file|connection timed out|could not connect|temporary failure resolving",
        "No network access, or the mirrors are unreachable: check the connection (nmcli, iwctl), then resume.",
    ),
    (
        "unable to lock database|db\\.lck|could not get lock /var/lib/dpkg",
        "Another package manager runs, or an earlier one was interrupted: wait for it, or remove its lock when none runs, then resume.",
    ),
    (
        "signature from .* is (unknown trust|invalid)|key .* could not be looked up|keyring is not writable|invalid or corrupted package|NO_PUBKEY",
        "Outdated package keyring: update it (sudo pacman -Sy archlinux-keyring, archlinuxarm-keyring on ARM), then resume.",
    ),
    (
        "conflicting files|exists in filesystem",
        "A file of the package already exists outside the package manager: check the files named above (remove or rename them), then resume.",
    ),
    (
        "target not found|unable to locate package",
        "The package is not in the enabled repositories (on ARM, some x86_64 packages do not exist): check its name, then resume.",
    ),
    (
        "sudo: (a password is required|a terminal is required)|is not in the sudoers",
        "sudo could not ask for your password: run the setup again from a terminal, it keeps sudo alive.",
    ),
    (
        "A failure occurred in (build|prepare|package|check)\\(\\)",
        "The build failed: read the error of the build tool above, then resume (the build starts over).",
    ),
    (
        "no space left on device",
        "The disk is full: free some space, then resume.",
    ),
    (
        "permission denied",
        "A permission problem: see the command and the file named above.",
    ),
];

const DEFAULT: &str = "See the log; fix the cause, then resume.";

/// The probable cause of a failure, from the last lines of its log.
pub(crate) fn probable_cause(tail: &str) -> &'static str {
    CAUSES
        .iter()
        .find(|(pattern, _)| {
            Regex::new(&format!("(?i){pattern}"))
                .expect("the cause patterns are valid")
                .is_match(tail)
        })
        .map(|(_, cause)| *cause)
        .unwrap_or(DEFAULT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_the_first_matching_cause() {
        assert!(
            probable_cause("error: failed retrieving file 'core.db'")
                .starts_with("No network access")
        );
        assert!(
            probable_cause("E: Unable to locate package foo").starts_with("The package is not in")
        );
        assert!(probable_cause("Permission Denied").starts_with("A permission problem"));
        assert_eq!(probable_cause("something else"), DEFAULT);
    }
}
