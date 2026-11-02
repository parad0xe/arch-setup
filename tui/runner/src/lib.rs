//! Running a plan. Each step is a unit: its packages, AUR packages,
//! services, files and hooks, in this order, each phase in the log of the
//! step. The status of each step goes to the run folder; what happens goes
//! to an [`Observer`], which the binary implements to show it.
//!
//! The hooks run through `lib/hook.sh` of the repository with the
//! environment of [`contract`]. Ctrl-C ([`Interrupt`]) stops the step
//! cleanly: a package tool is left to finish its current package.

mod answers;
mod commands;
pub mod contract;
mod deploy;
mod error;
mod executor;
mod hints;
mod interrupt;
mod observer;
mod process;

pub use answers::Answers;
pub use commands::Commands;
pub use error::RunnerError;
pub use executor::{ExecConfig, Executor, RunOutcome, RunStatus, Timing};
pub use interrupt::Interrupt;
pub use observer::{
    Failure, Observer, Phase, Progress, SkipReason, StepActions, StepOutcome, StepView,
};
