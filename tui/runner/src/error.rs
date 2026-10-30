use std::io;
use std::path::PathBuf;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum RunnerError {
    #[error("the run names a unit the setup no longer has: {0}")]
    UnknownUnit(String),
    #[error("{path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: io::Error,
    },
    #[error("starting {program}: {source}")]
    Spawn {
        program: String,
        #[source]
        source: io::Error,
    },
    #[error("listening for Ctrl-C: {0}")]
    Signals(#[source] io::Error),
    #[error(transparent)]
    Journal(#[from] journal::JournalError),
}
