//! What the hooks and `lib/hook.sh` of the repository agree on: the
//! environment a hook receives, the exit code of an interrupted step, and
//! the markers of the logs.

/// The public repository, for the hooks.
pub const SETUP_DIR: &str = "SETUP_DIR";
/// The folder of the module of the hook (`modules/<id>` of its repository,
/// public or private): its `files/` are beside the hooks.
pub const MODULE_ROOT: &str = "SETUP_MODULE_ROOT";
/// The log of the step, where the messages of a hook go.
pub const STEP_LOG: &str = "SETUP_STEP_LOG";
/// A file receiving the last message of a background hook, for the spinner.
pub const STEP_STATUS: &str = "SETUP_STEP_STATUS";
/// `1` when stdout is the log (a background step).
pub const QUIET: &str = "UI_QUIET";
/// `1` in a dry run (hooks are not run; kept for the helpers).
pub const DRY_RUN: &str = "SETUP_DRY_RUN";
/// `1` when the questions are answered with their default.
pub const ASSUME_YES: &str = "SETUP_ASSUME_YES";
/// The platform: `HOST_DISTRO`, `HOST_ARCH`, `HOST_CPU`, `HOST_GPU`, `HOST_VM`,
/// `HOST_APPLE_SILICON`, `HOST_BOOTLOADER`, `HOST_FILESYSTEMS`; lists are
/// space-separated, flags `1` or `0`.
pub const HOST_PREFIX: &str = "HOST_";
/// The answer to each input of the unit: `INPUT_<ID>`.
pub const INPUT_PREFIX: &str = "INPUT_";
/// The option of each variant of the unit: `VARIANT_<ID>`.
pub const VARIANT_PREFIX: &str = "VARIANT_";

/// The exit code of a step ended by Ctrl-C.
pub const INTERRUPTED: i32 = 130;
/// What `lib/core.sh` writes before the command that failed.
pub const FAILED_COMMAND: &str = "[error] Command failed";
/// The first character of the header lines of a step log.
pub const LOG_COMMENT: &str = "# ";

/// The environment variable of a fact, input or variant: upper case, dashes
/// as underscores.
pub fn variable(prefix: &str, id: &str) -> String {
    format!("{prefix}{}", id.to_uppercase().replace('-', "_"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn variables_are_upper_case() {
        assert_eq!(variable(INPUT_PREFIX, "email"), "INPUT_EMAIL");
        assert_eq!(variable(VARIANT_PREFIX, "key-binds"), "VARIANT_KEY_BINDS");
        assert_eq!(variable(HOST_PREFIX, "apple_silicon"), "HOST_APPLE_SILICON");
    }
}
