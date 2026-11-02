use std::io;
use std::path::PathBuf;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum JournalError {
    #[error("{path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: io::Error,
    },
    #[error("{path}: no plan")]
    NoPlan { path: PathBuf },
    #[error("{path}: step {index} does not exist ({steps} steps)")]
    NoSuchStep {
        path: PathBuf,
        index: usize,
        steps: usize,
    },
}
