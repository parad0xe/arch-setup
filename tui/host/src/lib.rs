//! This machine: the [`Platform`](model::Platform) the manifests test, what the
//! machine is for the screens ([`Machine`]), whether the setup can run on
//! it ([`check`]), and sudo ([`authenticate`], [`KeepAlive`]).
//!
//! Everything is read from /proc, /sys, /etc and the tools of a minimal
//! installation; the parsing is separate from the reading, and tested.

mod checks;
mod error;
mod machine;
mod platform;
mod probe;
mod sudo;

pub use checks::{Action, CheckContext, CheckReport, DEFAULT_PACMAN_LOCK, Network, Problem, check};
pub use error::HostError;
pub use machine::{Machine, Usage, probe_machine};
pub use platform::probe_platform;
pub use sudo::{KeepAlive, authenticate, remove_pacman_lock};
