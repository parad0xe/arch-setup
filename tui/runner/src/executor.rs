//! The loop over the steps of a run: each unit's phases in order, their
//! output in the log of the step, the status in the run folder, and what
//! happens told to the observer.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

use journal::{Run, Status};
use model::{HookRun, Platform, Registry, Unit};

use crate::answers::Answers;
use crate::commands::{Commands, describe};
use crate::contract;
use crate::deploy::{self, Target};
use crate::error::RunnerError;
use crate::hints;
use crate::interrupt::Interrupt;
use crate::observer::{
    Failure, Observer, Phase, Progress, SkipReason, StepActions, StepOutcome, StepView,
};
use crate::process::{self, Running};

pub use crate::process::Timing;

/// How many lines of a failed step's log are quoted, and how many the
/// probable cause is read from.
const LOG_TAIL: usize = 15;
const HINT_TAIL: usize = 60;

/// What every run needs.
#[derive(Debug, Clone)]
pub struct ExecConfig {
    /// The public repository, `SETUP_DIR` of the hooks.
    pub public_root: PathBuf,
    /// `lib/hook.sh` of the public repository.
    pub hook_script: PathBuf,
    /// Where the files go.
    pub home: PathBuf,
    /// Nothing is run: the plan says what would.
    pub dry_run: bool,
    /// The questions are answered with their default: attended units are
    /// skipped.
    pub assume_yes: bool,
    /// A terminal is there for the attended units.
    pub terminal: bool,
    /// Only the files of each unit are deployed, then its hooks run, so
    /// that the configs take effect: no packages nor services.
    pub files_only: bool,
    pub commands: Commands,
    pub timing: Timing,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunStatus {
    Completed,
    Failed,
    Interrupted,
}

/// How a run ended.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunOutcome {
    pub status: RunStatus,
    pub done: usize,
    pub skipped: usize,
    pub duration: Duration,
}

/// Runs the steps of runs, for one registry on one machine.
pub struct Executor<'a> {
    config: ExecConfig,
    registry: &'a Registry,
    platform: &'a Platform,
    /// The repositories the modules come from: nothing is deployed into
    /// them through a link.
    repositories: Vec<PathBuf>,
}

/// What a running phase is watched with.
struct Watch<'a, 'u> {
    view: &'a StepView<'u>,
    log: &'a Path,
    interrupt: &'a Interrupt,
}

/// How a phase ended.
enum PhaseEnd {
    Ok,
    Failed(i32),
    Interrupted,
}

impl<'a> Executor<'a> {
    pub fn new(config: ExecConfig, registry: &'a Registry, platform: &'a Platform) -> Executor<'a> {
        // Two folders up from modules/<id>
        let mut repositories: Vec<PathBuf> = registry
            .modules()
            .iter()
            .filter_map(|m| m.root().parent().and_then(Path::parent))
            .filter_map(|p| fs::canonicalize(p).ok())
            .collect();
        repositories.sort();
        repositories.dedup();
        Executor {
            config,
            registry,
            platform,
            repositories,
        }
    }

    /// Runs the steps of a run not done yet, in order, stopping at the
    /// first failure or on Ctrl-C.
    pub fn run(
        &self,
        run: &Run,
        answers: &Answers,
        interrupt: &Interrupt,
        observer: &mut dyn Observer,
    ) -> Result<RunOutcome, RunnerError> {
        let started = Instant::now();
        let total = run.steps().len();
        let mut status = RunStatus::Completed;
        for (i, id) in run.steps().iter().enumerate() {
            let unit = self
                .registry
                .unit(id)
                .ok_or_else(|| RunnerError::UnknownUnit(id.clone()))?;
            let view = StepView {
                index: i + 1,
                total,
                unit,
                attended: unit.attended(),
                earlier: run.status(id),
                actions: self.actions(unit, answers),
            };
            if view.earlier == Status::Done {
                observer.step_finished(&view, &StepOutcome::DoneEarlier);
                continue;
            }
            if interrupt.received() {
                status = RunStatus::Interrupted;
                break;
            }
            if view.attended
                && !self.config.dry_run
                && (!self.config.terminal || self.config.assume_yes)
            {
                run.record(id, Status::Skipped, None)?;
                observer.step_finished(&view, &StepOutcome::Skipped(SkipReason::Attended));
                continue;
            }

            let log = run.step_log(i + 1)?;
            write_header(&log, unit)?;
            run.record(id, Status::Started, None)?;
            observer.step_started(&view);
            let outcome = self.run_unit(&view, &log, answers, interrupt, observer)?;
            match &outcome {
                StepOutcome::Done { .. } => run.record(id, Status::Done, None)?,
                StepOutcome::Failed(failure) => {
                    run.record(id, Status::Failed, Some(failure.code))?;
                    status = RunStatus::Failed;
                }
                StepOutcome::Interrupted => {
                    run.record(id, Status::Interrupted, None)?;
                    status = RunStatus::Interrupted;
                }
                StepOutcome::DoneEarlier | StepOutcome::Skipped(_) => {}
            }
            observer.step_finished(&view, &outcome);
            if status != RunStatus::Completed {
                break;
            }
        }
        let done = run
            .steps()
            .iter()
            .filter(|id| run.status(id) == Status::Done)
            .count();
        let skipped = run
            .steps()
            .iter()
            .filter(|id| run.status(id) == Status::Skipped)
            .count();
        Ok(RunOutcome {
            status,
            done,
            skipped,
            duration: started.elapsed(),
        })
    }

    /// What a step would do on this machine.
    fn actions(&self, unit: &Unit, answers: &Answers) -> StepActions {
        let files_only = self.config.files_only;
        let unless_files_only = |items: Vec<String>| if files_only { Vec::new() } else { items };
        StepActions {
            packages: unless_files_only(unit.packages().to_vec()),
            aur: if self.platform.distro == "arch" {
                unless_files_only(unit.aur().to_vec())
            } else {
                Vec::new()
            },
            services: unless_files_only(unit.services().iter().map(|s| s.name.clone()).collect()),
            files: unit
                .files()
                .iter()
                .map(|f| {
                    (
                        deploy::resolve_source(unit, &f.source, answers)
                            .display()
                            .to_string(),
                        f.target.clone(),
                        f.mode,
                    )
                })
                .collect(),
            hooks: unit.hooks().map(str::to_string).collect(),
        }
    }

    /// The phases of a unit, in order; the first failure ends the step.
    fn run_unit(
        &self,
        view: &StepView,
        log: &Path,
        answers: &Answers,
        interrupt: &Interrupt,
        observer: &mut dyn Observer,
    ) -> Result<StepOutcome, RunnerError> {
        let unit = view.unit;
        let started = Instant::now();
        let distro = self.platform.distro.as_str();
        let commands = &self.config.commands;

        let watch = Watch {
            view,
            log,
            interrupt,
        };
        let mut phases: Vec<(Phase, Vec<Command>)> = Vec::new();
        if self.config.files_only {
            // The files and the hooks alone: no package nor service
        } else {
            if !unit.packages().is_empty() {
                phases.push((
                    Phase::Packages,
                    commands
                        .install(distro, unit.packages())
                        .into_iter()
                        .collect(),
                ));
            }
            if !unit.aur().is_empty() {
                phases.push((
                    Phase::Aur,
                    commands
                        .install_aur(distro, unit.aur())
                        .into_iter()
                        .collect(),
                ));
            }
            if !unit.services().is_empty() {
                phases.push((
                    Phase::Services,
                    unit.services().iter().map(|s| commands.enable(s)).collect(),
                ));
            }
        }
        for (phase, commands) in phases {
            for command in commands {
                match self.command_phase(&watch, &phase, command, false, observer)? {
                    PhaseEnd::Ok => {}
                    PhaseEnd::Failed(code) => return Ok(self.failure(phase, code, log, started)),
                    PhaseEnd::Interrupted => return Ok(StepOutcome::Interrupted),
                }
            }
        }

        if !unit.files().is_empty() {
            observer.step_progress(
                view,
                &Progress {
                    phase: Phase::Files,
                    message: None,
                    elapsed: started.elapsed(),
                },
            );
            if let Err(error) = self.files_phase(unit, answers, log) {
                append(
                    log,
                    &format!(
                        "{} {error}\n",
                        contract::FAILED_COMMAND.replace("Command", "File")
                    ),
                )?;
                return Ok(self.failure(Phase::Files, 1, log, started));
            }
        }

        for hook in unit.hook_runs() {
            let phase = Phase::Hook(hook.function.clone());
            let command = self.hook_command(unit, hook, answers, log);
            match self.command_phase(&watch, &phase, command, unit.attended(), observer)? {
                PhaseEnd::Ok => {}
                PhaseEnd::Failed(code) => return Ok(self.failure(phase, code, log, started)),
                PhaseEnd::Interrupted => return Ok(StepOutcome::Interrupted),
            }
        }
        Ok(StepOutcome::Done {
            duration: started.elapsed(),
        })
    }

    /// Runs one command of a phase, watched until it ends or Ctrl-C stops it.
    fn command_phase(
        &self,
        watch: &Watch,
        phase: &Phase,
        command: Command,
        foreground: bool,
        observer: &mut dyn Observer,
    ) -> Result<PhaseEnd, RunnerError> {
        append(
            watch.log,
            &format!(
                "{}{}: {}\n",
                contract::LOG_COMMENT,
                phase.describe(),
                describe(&command)
            ),
        )?;
        if self.config.dry_run {
            append(
                watch.log,
                &format!("{}dry run: not run\n", contract::LOG_COMMENT),
            )?;
            return Ok(PhaseEnd::Ok);
        }
        let status_file = (!foreground).then(|| watch.log.with_extension("status"));
        let mut running = process::spawn(
            command,
            watch.log,
            foreground,
            status_file,
            self.config.timing,
        )?;
        self.watch(&mut running, watch, phase, observer)
    }

    fn watch(
        &self,
        running: &mut Running,
        watch: &Watch,
        phase: &Phase,
        observer: &mut dyn Observer,
    ) -> Result<PhaseEnd, RunnerError> {
        loop {
            if watch.interrupt.received() {
                running.stop(watch.interrupt, |tool| observer.waiting_for(tool))?;
                return Ok(PhaseEnd::Interrupted);
            }
            for line in running.drain_lines() {
                observer.step_output(watch.view, &line);
            }
            if let Some(code) = running.poll()? {
                for line in running.drain_lines() {
                    observer.step_output(watch.view, &line);
                }
                if watch.interrupt.received() {
                    return Ok(PhaseEnd::Interrupted);
                }
                return Ok(if code == 0 {
                    PhaseEnd::Ok
                } else {
                    PhaseEnd::Failed(code)
                });
            }
            observer.step_progress(
                watch.view,
                &Progress {
                    phase: phase.clone(),
                    message: running.message(),
                    elapsed: running.elapsed(),
                },
            );
            thread::sleep(self.config.timing.poll);
        }
    }

    fn files_phase(
        &self,
        unit: &Unit,
        answers: &Answers,
        log: &Path,
    ) -> Result<(), deploy::DeployError> {
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(log)
            .map_err(|e| deploy::DeployError {
                file: log.display().to_string(),
                reason: e.to_string(),
            })?;
        let _ = writeln!(file, "{}deploying the files", contract::LOG_COMMENT);
        let target = Target {
            home: &self.config.home,
            sudo: &self.config.commands.sudo,
            dry_run: self.config.dry_run,
            repositories: &self.repositories,
        };
        for entry in unit.files() {
            deploy::deploy(unit, entry, answers, &target, &mut file)?;
        }
        Ok(())
    }

    /// The command of a hook, with the environment of the contract.
    /// The command of a hook: its module's `hooks.sh` (a fragment's for the
    /// hooks it brought), with the environment of the contract.
    fn hook_command(&self, unit: &Unit, hook: &HookRun, answers: &Answers, log: &Path) -> Command {
        let script = hook.module_root.join("hooks.sh");
        let mut command =
            self.config
                .commands
                .hook(&self.config.hook_script, &script, &hook.function);
        // The hooks and the files agree on the home folder
        command
            .env("HOME", &self.config.home)
            .env(contract::SETUP_DIR, &self.config.public_root)
            .env(contract::MODULE_ROOT, &hook.module_root)
            .env(contract::STEP_LOG, log)
            .env(
                contract::DRY_RUN,
                if self.config.dry_run { "1" } else { "0" },
            )
            .env(
                contract::ASSUME_YES,
                if self.config.assume_yes { "1" } else { "0" },
            );
        let flag = |value: bool| if value { "1" } else { "0" };
        let p = self.platform;
        for (name, value) in [
            ("distro", p.distro.clone()),
            ("arch", p.arch.clone()),
            ("cpu", p.cpu.clone()),
            ("gpu", p.gpu.join(" ")),
            ("vm", flag(p.vm).to_string()),
            ("apple_silicon", flag(p.apple_silicon).to_string()),
            ("bootloader", p.bootloader.clone()),
            ("filesystems", p.filesystems.join(" ")),
        ] {
            command.env(contract::variable(contract::HOST_PREFIX, name), value);
        }
        for (input, value) in answers.inputs_of(unit.id()) {
            command.env(contract::variable(contract::INPUT_PREFIX, input), value);
        }
        for (variant, option) in answers.variants_of(unit.id()) {
            command.env(
                contract::variable(contract::VARIANT_PREFIX, variant),
                option,
            );
        }
        command
    }

    /// A failed step, from its log.
    fn failure(&self, phase: Phase, code: i32, log: &Path, started: Instant) -> StepOutcome {
        let text = fs::read_to_string(log).unwrap_or_default();
        let lines: Vec<&str> = text.lines().collect();
        let log_tail: Vec<String> = lines
            .iter()
            .map(|l| l.replace('\r', ""))
            .filter(|l| {
                !l.is_empty()
                    && !l.starts_with(contract::FAILED_COMMAND)
                    && !(l.starts_with("    in ") && l.contains("() at "))
                    && !l.starts_with(contract::LOG_COMMENT)
            })
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .take(LOG_TAIL)
            .rev()
            .collect();
        let command = lines
            .iter()
            .rev()
            .find(|l| l.starts_with(contract::FAILED_COMMAND))
            .map(|l| l.split_once("): ").map(|(_, c)| c).unwrap_or(l).to_string());
        let tail: String = lines
            .iter()
            .rev()
            .take(HINT_TAIL)
            .rev()
            .copied()
            .collect::<Vec<_>>()
            .join("\n");
        StepOutcome::Failed(Failure {
            phase,
            code,
            duration: started.elapsed(),
            log: log.to_path_buf(),
            log_tail,
            command,
            cause: hints::probable_cause(&tail),
        })
    }
}

/// Starts the log of a step (after the log of an earlier attempt).
fn write_header(log: &Path, unit: &Unit) -> Result<(), RunnerError> {
    let existing = fs::metadata(log).map(|m| m.len() > 0).unwrap_or(false);
    let mut text = String::new();
    if existing {
        text.push('\n');
    }
    text.push_str(&format!(
        "{}unit {}: {}\n",
        contract::LOG_COMMENT,
        unit.id(),
        unit.name()
    ));
    append(log, &text)
}

fn append(log: &Path, text: &str) -> Result<(), RunnerError> {
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(log)
        .map_err(|source| RunnerError::Io {
            path: log.to_path_buf(),
            source,
        })?;
    file.write_all(text.as_bytes())
        .map_err(|source| RunnerError::Io {
            path: log.to_path_buf(),
            source,
        })
}
