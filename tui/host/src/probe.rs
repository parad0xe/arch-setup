//! Reading the machine: files and commands, each failure a `None`.

use std::fs;
use std::path::Path;
use std::process::{Command, Stdio};

/// The trimmed text of a file, when it can be read.
pub(crate) fn read(path: impl AsRef<Path>) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|text| text.trim_matches(['\0', '\n', ' ']).to_string())
}

/// The trimmed stdout of a command that succeeds.
pub(crate) fn output(program: &str, args: &[&str]) -> Option<String> {
    let output = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Whether a command runs and succeeds, its output dropped.
pub(crate) fn succeeds(program: &str, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

/// Whether a program is found on the PATH.
pub(crate) fn installed(program: &str) -> bool {
    succeeds("sh", &["-c", &format!("command -v {program}")])
}
