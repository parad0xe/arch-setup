//! What the binary is told about a run while it happens.

use std::path::PathBuf;
use std::time::Duration;

use journal::Status;
use model::{Mode, Unit};

/// The declared parts of a step, for the machine: what a dry run would do.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct StepActions {
    pub packages: Vec<String>,
    pub aur: Vec<String>,
    pub services: Vec<String>,
    /// (source, target, mode)
    pub files: Vec<(String, String, Mode)>,
    pub hooks: Vec<String>,
}

/// A step of the run, as the observer sees it.
#[derive(Debug, Clone)]
pub struct StepView<'a> {
    /// From 1.
    pub index: usize,
    pub total: usize,
    pub unit: &'a Unit,
    /// Runs in the foreground, with the terminal.
    pub attended: bool,
    /// Its status before this run started it.
    pub earlier: Status,
    pub actions: StepActions,
}

/// What a step is doing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Phase {
    Packages,
    Aur,
    Services,
    Files,
    Hook(String),
}

impl Phase {
    /// What the phase does, for a status line.
    pub fn describe(&self) -> String {
        match self {
            Phase::Packages => "installing the packages".to_string(),
            Phase::Aur => "installing the AUR packages".to_string(),
            Phase::Services => "enabling the services".to_string(),
            Phase::Files => "deploying the files".to_string(),
            Phase::Hook(function) => format!("running {function}"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Progress {
    pub phase: Phase,
    /// The last message of a hook.
    pub message: Option<String>,
    pub elapsed: Duration,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SkipReason {
    /// The step needs the terminal and there is none, or --yes.
    Attended,
}

/// A failed step: what to show.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Failure {
    pub phase: Phase,
    pub code: i32,
    pub duration: Duration,
    pub log: PathBuf,
    /// The last meaningful lines of the log.
    pub log_tail: Vec<String>,
    /// The command bash reported as failed, in a hook.
    pub command: Option<String>,
    pub cause: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StepOutcome {
    Done {
        duration: Duration,
    },
    /// Done in an earlier attempt: not run again.
    DoneEarlier,
    Skipped(SkipReason),
    Failed(Failure),
    Interrupted,
}

/// Told what happens; implemented by the binary.
pub trait Observer {
    /// The step starts running.
    fn step_started(&mut self, step: &StepView);
    /// Now and then while the step runs.
    fn step_progress(&mut self, step: &StepView, progress: &Progress);
    /// A line a foreground step printed.
    fn step_output(&mut self, step: &StepView, line: &str);
    fn step_finished(&mut self, step: &StepView, outcome: &StepOutcome);
    /// A package tool is left to finish its current package.
    fn waiting_for(&mut self, tool: &str);
}
