//! sudo: asking for the password, keeping the rights alive during a run,
//! removing a stale pacman lock.

use std::path::Path;
use std::process::Command;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use crate::error::HostError;
use crate::probe::succeeds;

/// How often the rights are refreshed (sudo forgets them after 15 minutes
/// by default).
const REFRESH: Duration = Duration::from_secs(50);

/// Asks for the sudo password now (`sudo -v`), on the terminal.
pub fn authenticate() -> Result<(), HostError> {
    let status = Command::new("sudo")
        .arg("-v")
        .status()
        .map_err(|source| HostError::Command {
            program: "sudo".to_string(),
            source,
        })?;
    if status.success() {
        Ok(())
    } else {
        Err(HostError::SudoRefused)
    }
}

/// Removes a pacman lock with sudo.
pub fn remove_pacman_lock(path: &Path) -> Result<(), HostError> {
    if succeeds("sudo", &["rm", "-f", &path.to_string_lossy()]) && !path.exists() {
        Ok(())
    } else {
        Err(HostError::LockNotRemoved(path.to_path_buf()))
    }
}

/// Keeps the sudo rights alive while it lives, so that no step waits for a
/// password it cannot ask for.
pub struct KeepAlive {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl KeepAlive {
    pub fn start() -> KeepAlive {
        let stop = Arc::new(AtomicBool::new(false));
        let flag = Arc::clone(&stop);
        let thread = thread::spawn(move || {
            while !flag.load(Ordering::SeqCst) {
                succeeds("sudo", &["-n", "true"]);
                let mut slept = Duration::ZERO;
                while slept < REFRESH && !flag.load(Ordering::SeqCst) {
                    thread::sleep(Duration::from_secs(1));
                    slept += Duration::from_secs(1);
                }
            }
        });
        KeepAlive {
            stop,
            thread: Some(thread),
        }
    }
}

impl Drop for KeepAlive {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}
