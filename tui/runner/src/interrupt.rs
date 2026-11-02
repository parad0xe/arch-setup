//! Ctrl-C, counted: the first stops the run after the step, another while a
//! package tool is waited for leaves it running.

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;

use signal_hook::consts::{SIGINT, SIGTERM};
use signal_hook::iterator::Signals;

use crate::error::RunnerError;

#[derive(Debug, Clone, Default)]
pub struct Interrupt(Arc<AtomicUsize>);

impl Interrupt {
    /// Listens for Ctrl-C and termination signals from now on.
    pub fn install() -> Result<Interrupt, RunnerError> {
        let count = Arc::new(AtomicUsize::new(0));
        let mut signals = Signals::new([SIGINT, SIGTERM]).map_err(RunnerError::Signals)?;
        let counter = Arc::clone(&count);
        thread::spawn(move || {
            for _ in signals.forever() {
                counter.fetch_add(1, Ordering::SeqCst);
            }
        });
        Ok(Interrupt(count))
    }

    /// One that never fires, for the tests and the dry runs.
    pub fn never() -> Interrupt {
        Interrupt::default()
    }

    /// Counts one as if a signal arrived (the tests).
    pub fn raise(&self) {
        self.0.fetch_add(1, Ordering::SeqCst);
    }

    pub fn count(&self) -> usize {
        self.0.load(Ordering::SeqCst)
    }

    pub fn received(&self) -> bool {
        self.count() > 0
    }
}
