use std::io;
use std::path::PathBuf;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum HostError {
    #[error("running {program}: {source}")]
    Command {
        program: String,
        #[source]
        source: io::Error,
    },
    #[error("sudo refused, or the password prompt was cancelled")]
    SudoRefused,
    #[error("{0} could not be removed")]
    LockNotRemoved(PathBuf),
}
