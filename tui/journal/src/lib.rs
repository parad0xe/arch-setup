//! The runs: a folder each under a state folder, holding the plan (the
//! units in run order), the status of each step, the variants and the
//! answers of the run, and the logs; the latest run is linked as `latest`.
//! A run that did not finish is resumed: its done steps are skipped.
//!
//! Files of a run:
//!
//! ```text
//! meta       key=value lines: profile, started, dry_run, files_only, machine, argv, private, abandoned
//! plan       "unit <id>" lines, in run order
//! variants   "<unit> <variant> <option>" lines
//! inputs     "<unit> <input> <value>" lines (secrets left out by the caller)
//! status     "<epoch> unit <id> <status> [code]" lines, appended: the last one of a step wins
//! setup.log  what the setup printed
//! steps/     one log per step: NN-<id>.log
//! ```
//!
//! Plain strings only: the crate knows neither the model nor the machine.

mod error;
mod run;
mod store;

pub use error::JournalError;
pub use run::{Run, Status};
pub use store::{NewRun, RUNS_KEPT, RunStore};
