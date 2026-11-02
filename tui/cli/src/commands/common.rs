//! What every command builds on: the setup (the repositories read, the
//! platform, the registry, the profiles, the runs), the checks before a run
//! with their actions, the answers still to ask, and the run itself.

use std::collections::BTreeMap;
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use host::{Action, CheckContext, KeepAlive, Network, Problem};
use journal::{NewRun, RUNS_KEPT, Run, RunStore};
use model::{Input, InputKind, Plan, Platform, Profiles, Registry, Selection, Unit, plan};
use repo::Repository;
use runner::{Answers, Commands, ExecConfig, Executor, Interrupt, RunStatus, Timing, contract};

use crate::config::Config;
use crate::console::{Console, RunView};
use crate::private::Private;

/// The setup as read for this launch.
pub struct Setup {
    pub config: Config,
    pub public: Repository,
    pub private: Option<Private>,
    pub platform: Platform,
    pub registry: Registry,
    pub profiles: Profiles,
    pub store: RunStore,
}

impl Setup {
    /// Reads the public repository, then the private one; the profiles of
    /// the private repository win over the public ones of the same name,
    /// the user's over both.
    pub fn load(config: Config, private: Option<Private>) -> Result<Setup> {
        let public_root = config.public_root()?;
        let public = Repository::open(public_root)
            .with_context(|| format!("opening the repository {}", public_root.display()))?;
        let mut repositories = vec![public.clone()];
        if let Some(private) = &private {
            let repository = Repository::open(&private.root).with_context(|| {
                format!("opening the private repository {}", private.root.display())
            })?;
            repositories.push(repository);
        }
        let declarations = Repository::load(&repositories).context("reading the modules")?;
        let platform = host::probe_platform();
        let registry = Registry::new(declarations, &platform).context("checking the modules")?;
        let mut by_name = BTreeMap::new();
        for repository in &repositories {
            for profile in repository.profiles().context("reading the profiles")? {
                by_name.insert(profile.name.clone(), profile);
            }
        }
        for profile in repo::read_profiles(&config.profiles_dir)
            .with_context(|| format!("reading the profiles of {}", config.profiles_dir.display()))?
        {
            by_name.insert(profile.name.clone(), profile);
        }
        let profiles = Profiles::new(by_name.into_values()).context("checking the profiles")?;
        let store = RunStore::new(&config.state_dir);
        Ok(Setup {
            config,
            public,
            private,
            platform,
            registry,
            profiles,
            store,
        })
    }

    /// An unfinished run to offer, never before a dry run.
    pub fn unfinished(&self) -> Result<Option<Run>> {
        if self.config.dry_run {
            return Ok(None);
        }
        Ok(self.store.resumable()?)
    }
}

/// Whether the run may start, after the checks.
enum Readiness {
    /// sudo is kept alive until the guard is dropped (not in a dry run).
    Ready(Option<KeepAlive>),
    /// The problems were printed.
    Blocked,
}

/// Checks the machine, takes the actions the user agrees to (the sudo
/// password, a stale pacman lock), and prints what prevents the run. In a
/// dry run the problems only warn.
fn prepare(setup: &Setup, console: &mut Console) -> Result<Readiness> {
    let strict = !setup.config.dry_run;
    let context = CheckContext {
        platform: &setup.platform,
        distributions: Platform::distributions(),
        strict,
        assume_yes: setup.config.assume_yes,
        terminal: console.terminal(),
        pacman_lock: setup.config.pacman_lock.clone(),
        network: Network::default(),
    };
    let mut report = host::check(&context);
    for action in std::mem::take(&mut report.actions) {
        match action {
            Action::AskSudoPassword => {
                console.text("  The system steps run with sudo.");
                if let Err(error) = host::authenticate() {
                    report.problems.push(Problem {
                        what: format!("{error}."),
                        fix: "As root, usermod -aG wheel $USER and allow the wheel group in sudoers, then log in again.".to_string(),
                    });
                }
            }
            Action::RemovePacmanLock { path, declined } => {
                let question = format!(
                    "A pacman lock remains from an interrupted run ({}). Remove it?",
                    path.display()
                );
                let removed = console.can_prompt()
                    && console.confirm(&question, false)?
                    && host::remove_pacman_lock(&path).is_ok();
                if !removed {
                    report.problems.push(declined);
                }
            }
        }
    }
    for note in &report.notes {
        console.warn(note);
    }
    if report.problems.is_empty() {
        return Ok(Readiness::Ready(strict.then(KeepAlive::start)));
    }
    if strict {
        console.error("The setup cannot run on this machine:");
    } else {
        console.warn("The setup would not run on this machine (ignored for the dry run):");
    }
    let dot = console.glyphs.dot;
    for problem in &report.problems {
        console.text(&format!("  {dot} {} {}", problem.what, problem.fix));
    }
    Ok(if strict {
        Readiness::Blocked
    } else {
        Readiness::Ready(None)
    })
}

/// Asks the answers these units still need (no answer, no default); fails
/// when one is required and no terminal can ask.
fn complete_answers<'a>(
    console: &mut Console,
    units: impl IntoIterator<Item = &'a Unit>,
    answers: &mut Answers,
) -> Result<()> {
    for unit in units {
        for input in answers.missing(unit) {
            if !console.can_prompt() {
                if input.required {
                    bail!(
                        "{}: the answer {} is required: give it in a profile ([inputs] \"{}.{}\" = ...) or run from a terminal without --yes",
                        unit.id(),
                        input.id,
                        unit.id(),
                        input.id
                    );
                }
                continue;
            }
            let value = ask_input(console, unit, input)?;
            if !value.is_empty() {
                answers.set_input(unit.id(), &input.id, &value);
            }
        }
    }
    Ok(())
}

/// One question on the console, as the hooks receive the answer.
fn ask_input(console: &mut Console, unit: &Unit, input: &Input) -> Result<String> {
    let prompt = format!("{} ({})", input.prompt, unit.id());
    match input.kind {
        InputKind::Bool => {
            let yes = console.confirm(&prompt, input.default.as_deref() == Some("true"))?;
            Ok(if yes { "1" } else { "0" }.to_string())
        }
        InputKind::Secret => loop {
            let value = console.ask_secret(&prompt)?;
            if !value.is_empty() || !input.required {
                return Ok(value);
            }
            console.warn("An answer is required.");
        },
        InputKind::Choice => {
            let values: Vec<&str> = input.options.iter().map(|o| o.value.as_str()).collect();
            let shown = format!(
                "{prompt} [{}]{}",
                values.join("/"),
                if input.custom {
                    " or another value"
                } else {
                    ""
                }
            );
            loop {
                let value = console.ask(&shown, input.default.as_deref())?;
                if values.contains(&value.as_str()) || (input.custom && !value.is_empty()) {
                    return Ok(value);
                }
                console.warn(&format!("One of: {}.", values.join(", ")));
            }
        }
        InputKind::Text => loop {
            let value = console.ask(&prompt, input.default.as_deref())?;
            if !value.is_empty() || !input.required {
                return Ok(value);
            }
            console.warn("An answer is required.");
        },
    }
}

/// Starts a new run of a selection, after the questions and the checks; an
/// unfinished run is left aside once the new one is sure to start.
pub fn start(
    setup: &Setup,
    console: &mut Console,
    profile: &str,
    selection: &Selection,
    unfinished: Option<Run>,
) -> Result<ExitCode> {
    let files_only = setup.config.files_only;
    let mut plan = plan::build(&setup.registry, selection);
    if files_only {
        // The units with files alone: their files, then their hooks
        plan = plan.keeping(|s| {
            setup
                .registry
                .unit(s.unit())
                .is_some_and(|u| !u.files().is_empty())
        });
    }
    if plan.is_empty() {
        console.warn(if files_only {
            "Nothing to deploy: no selected unit has files."
        } else {
            "Nothing to run: no unit selected."
        });
        return Ok(ExitCode::SUCCESS);
    }
    for (unit, by) in plan.left_out() {
        console.warn(&format!(
            "{unit}, required by {by}, is not for this machine: left out."
        ));
    }
    let mut answers = Answers::from_selection(&setup.registry, selection);
    complete_answers(console, planned_units(&setup.registry, &plan), &mut answers)?;
    // The checks guard the system steps: the files and the hooks skip them
    let keep_alive = if files_only {
        None
    } else {
        match prepare(setup, console)? {
            Readiness::Ready(keep_alive) => keep_alive,
            Readiness::Blocked => return Ok(ExitCode::FAILURE),
        }
    };
    if let Some(old) = unfinished {
        old.abandon()?;
        console.info(&format!(
            "Leaving the unfinished run aside; its logs stay in {}.",
            setup.config.tilde(old.dir())
        ));
    }
    let run = setup.store.create(&NewRun {
        profile: profile.to_string(),
        steps: plan.steps().iter().map(|s| s.unit().to_string()).collect(),
        variants: answers.variants(),
        inputs: answers.inputs_without_secrets(&setup.registry),
        dry_run: setup.config.dry_run,
        machine: setup.platform.arch.clone(),
        argv: setup.config.argv.clone(),
        private: setup.private.as_ref().map(|p| p.source.clone()),
        files_only,
    })?;
    setup.store.prune(RUNS_KEPT)?;
    let code = execute(setup, console, &run, &answers)?;
    drop(keep_alive);
    Ok(code)
}

fn planned_units<'a>(registry: &'a Registry, plan: &'a Plan) -> impl Iterator<Item = &'a Unit> {
    plan.steps()
        .iter()
        .filter_map(|step| registry.unit(step.unit()))
}

/// Runs the steps of an unfinished run not done yet, after the checks; the
/// secrets, never recorded, are asked again.
pub fn resume(setup: &Setup, console: &mut Console, run: &Run) -> Result<ExitCode> {
    for id in run.steps() {
        if setup.registry.unit(id).is_none() {
            bail!(
                "cannot resume the {}: its step {id} no longer exists (the setup changed). Start a new run.",
                run.describe()
            );
        }
    }
    let mut answers = Answers::from_recorded(run.variants(), run.inputs());
    let remaining = run
        .steps()
        .iter()
        .filter(|id| !run.status(id).is_finished())
        .filter_map(|id| setup.registry.unit(id));
    complete_answers(console, remaining, &mut answers)?;
    let Readiness::Ready(keep_alive) = prepare(setup, console)? else {
        return Ok(ExitCode::FAILURE);
    };
    console.info(&format!("Resuming the {}.", run.describe()));
    let code = execute(setup, console, run, &answers)?;
    drop(keep_alive);
    Ok(code)
}

/// Runs a run on the console, its lines copied to its setup.log.
fn execute(setup: &Setup, console: &mut Console, run: &Run, answers: &Answers) -> Result<ExitCode> {
    let interrupt = Interrupt::install()?;
    console.open_log(&run.setup_log())?;
    let resume_command = format!("{} resume", setup.config.program);
    let config = ExecConfig {
        public_root: setup.public.root().to_path_buf(),
        hook_script: setup.public.hook_script(),
        home: setup.config.home.clone(),
        dry_run: setup.config.dry_run,
        assume_yes: setup.config.assume_yes,
        terminal: console.terminal(),
        files_only: setup.config.files_only,
        commands: Commands::default(),
        timing: Timing::default(),
    };
    let mut view = RunView::new(
        console,
        run,
        resume_command,
        setup.config.dry_run,
        setup.config.files_only,
        &setup.config.home,
    );
    view.print_plan(run, &setup.registry);
    let outcome = Executor::new(config, &setup.registry, &setup.platform)
        .run(run, answers, &interrupt, &mut view)?;
    view.summary(run, &outcome);
    console.close_log();
    Ok(match outcome.status {
        RunStatus::Completed => ExitCode::SUCCESS,
        RunStatus::Failed => ExitCode::FAILURE,
        RunStatus::Interrupted => ExitCode::from(u8::try_from(contract::INTERRUPTED).unwrap_or(1)),
    })
}
