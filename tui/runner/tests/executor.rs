//! A run from end to end, with fake tools and the real lib/hook.sh.

use std::fs;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::{Path, PathBuf};

use journal::{NewRun, RunStore, Status};
use model::{
    Declarations, FileEntry, Fragment, Hook, Input, InputKind, Merge, Mode, ModuleDeclaration,
    Package, Platform, Registry, Selection, Service, UnitDeclaration,
};
use runner::{
    Answers, Commands, ExecConfig, Executor, Interrupt, Observer, Progress, RunStatus, StepOutcome,
    StepView, Timing,
};

/// Records what the executor tells.
#[derive(Default)]
struct Recorder {
    events: Vec<String>,
    outcomes: Vec<(String, StepOutcome)>,
}

impl Observer for Recorder {
    fn step_started(&mut self, step: &StepView) {
        self.events.push(format!("started {}", step.unit.id()));
    }
    fn step_progress(&mut self, _step: &StepView, _progress: &Progress) {}
    fn step_output(&mut self, step: &StepView, line: &str) {
        self.events
            .push(format!("output {}: {line}", step.unit.id()));
    }
    fn step_finished(&mut self, step: &StepView, outcome: &StepOutcome) {
        self.events.push(format!("finished {}", step.unit.id()));
        self.outcomes
            .push((step.unit.id().to_string(), outcome.clone()));
    }
    fn waiting_for(&mut self, tool: &str) {
        self.events.push(format!("waiting {tool}"));
    }
}

/// A sandbox: a repository with the real lib/, a module script, files, fake
/// tools and a home.
struct Sandbox {
    dir: tempfile::TempDir,
    repo: PathBuf,
    home: PathBuf,
    fake_log: PathBuf,
}

fn sandbox() -> Sandbox {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    let repo = root.join("repo");
    let home = root.join("home");
    fs::create_dir_all(repo.join("modules/demo/files/bin")).unwrap();
    fs::create_dir_all(&home).unwrap();
    let real_lib =
        fs::canonicalize(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../lib")).unwrap();
    symlink(&real_lib, repo.join("lib")).unwrap();
    fs::write(repo.join("modules/demo/files/conf"), "conf\n").unwrap();
    fs::write(repo.join("modules/demo/files/bin/tool"), "#!/bin/sh\n").unwrap();
    fs::write(
        repo.join("modules/demo/hooks.sh"),
        "greet() {\n    log_info \"Hello $INPUT_NAME from $VARIANT_THEME on $HOST_DISTRO\"\n    echo \"$INPUT_NAME\" > \"$HOME/greeted\"\n}\n\nfailing() {\n    log_info \"before\"\n    false\n    log_info \"after\"\n}\n",
    )
    .unwrap();
    let bin = root.join("bin");
    fs::create_dir_all(&bin).unwrap();
    let fake_log = root.join("fake.log");
    for tool in ["pacman", "yay", "systemctl"] {
        let path = bin.join(tool);
        fs::write(
            &path,
            format!(
                "#!/bin/bash\necho \"{tool} $*\" >> \"{}\"\n",
                fake_log.display()
            ),
        )
        .unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    }
    fs::write(bin.join("sudo"), "#!/bin/bash\nexec \"$@\"\n").unwrap();
    fs::set_permissions(bin.join("sudo"), fs::Permissions::from_mode(0o755)).unwrap();
    Sandbox {
        dir,
        repo,
        home,
        fake_log,
    }
}

fn unit(id: &str) -> UnitDeclaration {
    UnitDeclaration {
        id: id.into(),
        name: format!("{id} unit"),
        ..Default::default()
    }
}

fn declarations(repo: &Path) -> Declarations {
    let mut tools = unit("tools");
    tools.packages = vec![
        Package {
            name: "git".into(),
            when: None,
        },
        Package {
            name: "curl".into(),
            when: None,
        },
    ];
    tools.aur = vec![Package {
        name: "paru".into(),
        when: None,
    }];
    tools.services = vec![Service {
        name: "svc".into(),
        now: true,
        force: false,
    }];
    tools.files = vec![
        FileEntry {
            source: "files/conf".into(),
            target: ".conf".into(),
            mode: Mode::Symlink,
            contents: false,
            backup: true,
            permissions: None,
        },
        FileEntry {
            source: "files/bin".into(),
            target: ".local/bin".into(),
            mode: Mode::Copy,
            contents: true,
            backup: false,
            permissions: Some(0o755),
        },
    ];
    tools.variants = vec![model::Variant {
        id: "theme".into(),
        name: "T".into(),
        options: vec!["dark".into(), "light".into()],
        default: None,
    }];
    tools.files.push(FileEntry {
        source: "files/{theme}".into(),
        target: ".theme".into(),
        mode: Mode::Symlink,
        contents: false,
        backup: true,
        permissions: None,
    });
    tools.inputs = vec![Input {
        id: "name".into(),
        prompt: "Name".into(),
        kind: InputKind::Text,
        ..Default::default()
    }];
    tools.hooks = vec![Hook {
        run: "greet".into(),
        when: None,
    }];
    let mut broken = unit("broken");
    broken.hooks = vec![Hook {
        run: "failing".into(),
        when: None,
    }];
    let mut asker = unit("asker");
    asker.attended = true;
    asker.hooks = vec![Hook {
        run: "greet".into(),
        when: None,
    }];
    let module = ModuleDeclaration {
        id: "demo".into(),
        name: "Demo".into(),
        about: None,
        root: repo.join("modules/demo"),
        units: vec![tools, broken, asker],
        fragments: Vec::new(),
    };
    Declarations {
        modules: vec![module],
    }
}

fn registry(repo: &Path) -> Registry {
    Registry::new(declarations(repo), &platform()).unwrap()
}

fn platform() -> Platform {
    Platform {
        distro: "arch".into(),
        arch: "x86_64".into(),
        cpu: "intel".into(),
        bootloader: "grub".into(),
        ..Default::default()
    }
}

fn config(sb: &Sandbox, dry_run: bool, assume_yes: bool) -> ExecConfig {
    let bin = sb.dir.path().join("bin");
    let program = |name: &str| bin.join(name).display().to_string();
    ExecConfig {
        public_root: sb.repo.clone(),
        hook_script: sb.repo.join("lib/hook.sh"),
        home: sb.home.clone(),
        dry_run,
        assume_yes,
        terminal: false,
        files_only: false,
        commands: Commands {
            sudo: program("sudo"),
            bash: "bash".into(),
            pacman: program("pacman"),
            yay: program("yay"),
            apt_get: "apt-get".into(),
            systemctl: program("systemctl"),
        },
        timing: Timing {
            poll: std::time::Duration::from_millis(20),
            ..Timing::default()
        },
    }
}

fn new_run(steps: &[&str], answers: &Answers, dry_run: bool) -> NewRun {
    NewRun {
        profile: "test".into(),
        steps: steps.iter().map(|s| s.to_string()).collect(),
        variants: answers.variants(),
        inputs: Vec::new(),
        dry_run,
        machine: "x86_64".into(),
        argv: String::new(),
        private: None,
        files_only: false,
    }
}

#[test]
fn a_run_installs_enables_deploys_and_hooks() {
    let sb = sandbox();
    fs::write(sb.repo.join("modules/demo/files/dark"), "dark\n").unwrap();
    fs::write(sb.repo.join("modules/demo/files/light"), "light\n").unwrap();
    let registry = registry(&sb.repo);
    let store = RunStore::new(sb.dir.path().join("state"));
    let mut selection = Selection::new();
    selection.set_input("tools", "name", model::InputValue::Text("world".into()));
    selection.set_variant("tools", "theme", "light");
    let answers = Answers::from_selection(&registry, &selection);
    let run = store.create(&new_run(&["tools"], &answers, false)).unwrap();
    let mut recorder = Recorder::default();

    let outcome = Executor::new(config(&sb, false, false), &registry, &platform())
        .run(&run, &answers, &Interrupt::never(), &mut recorder)
        .unwrap();
    assert_eq!(
        outcome.status,
        RunStatus::Completed,
        "{:?}",
        recorder.outcomes
    );
    assert_eq!((outcome.done, outcome.skipped), (1, 0));
    assert_eq!(run.status("tools"), Status::Done);
    let calls = fs::read_to_string(&sb.fake_log).unwrap_or_else(|e| {
        panic!(
            "{e}; step log:\n{}",
            fs::read_to_string(run.step_log(1).unwrap()).unwrap_or_default()
        )
    });
    assert!(
        calls.contains("pacman -S --needed --noconfirm --ask=4 git curl"),
        "{calls}"
    );
    assert!(
        calls.contains("yay -S --needed --noconfirm paru"),
        "{calls}"
    );
    assert!(calls.contains("systemctl enable --now svc"), "{calls}");
    assert_eq!(
        fs::read_link(sb.home.join(".conf")).unwrap(),
        sb.repo.join("modules/demo/files/conf")
    );
    assert_eq!(
        fs::read_link(sb.home.join(".theme")).unwrap(),
        sb.repo.join("modules/demo/files/light"),
        "the picked variant"
    );
    let mode = fs::metadata(sb.home.join(".local/bin/tool"))
        .unwrap()
        .permissions()
        .mode()
        & 0o777;
    assert_eq!(mode, 0o755);
    assert_eq!(
        fs::read_to_string(sb.home.join("greeted")).unwrap(),
        "world\n"
    );
    let log = fs::read_to_string(run.step_log(1).unwrap()).unwrap();
    assert!(log.contains("# unit tools: tools unit"), "{log}");
    assert!(log.contains("[i] Hello world from light on arch"), "{log}");
    assert!(log.contains("linked") && log.contains("copied"), "{log}");
    assert_eq!(
        recorder.events.first().map(String::as_str),
        Some("started tools")
    );
    assert!(matches!(recorder.outcomes[0].1, StepOutcome::Done { .. }));

    // Run again: nothing to do, the files are unchanged
    let run2 = store.create(&new_run(&["tools"], &answers, false)).unwrap();
    Executor::new(config(&sb, false, false), &registry, &platform())
        .run(
            &run2,
            &answers,
            &Interrupt::never(),
            &mut Recorder::default(),
        )
        .unwrap();
    let log = fs::read_to_string(run2.step_log(1).unwrap()).unwrap();
    assert_eq!(log.matches("unchanged").count(), 3, "{log}");
    assert!(!sb.home.join(".conf.bak").exists());
}

#[test]
fn a_failing_hook_stops_the_run_and_the_resume_skips_the_done_steps() {
    let sb = sandbox();
    fs::write(sb.repo.join("modules/demo/files/dark"), "").unwrap();
    fs::write(sb.repo.join("modules/demo/files/light"), "").unwrap();
    let registry = registry(&sb.repo);
    let store = RunStore::new(sb.dir.path().join("state"));
    let mut selection = Selection::new();
    selection.set_input("tools", "name", model::InputValue::Text("x".into()));
    let answers = Answers::from_selection(&registry, &selection);
    let run = store
        .create(&new_run(&["tools", "broken", "asker"], &answers, false))
        .unwrap();
    let mut recorder = Recorder::default();

    let outcome = Executor::new(config(&sb, false, false), &registry, &platform())
        .run(&run, &answers, &Interrupt::never(), &mut recorder)
        .unwrap();
    assert_eq!(outcome.status, RunStatus::Failed);
    assert_eq!(run.status("tools"), Status::Done);
    assert_eq!(run.status("broken"), Status::Failed);
    assert_eq!(run.code("broken"), Some(1));
    assert_eq!(
        run.status("asker"),
        Status::Pending,
        "the run stopped before it"
    );
    let StepOutcome::Failed(failure) = &recorder.outcomes[1].1 else {
        panic!("{:?}", recorder.outcomes)
    };
    assert_eq!(failure.command.as_deref(), Some("false"));
    assert_eq!(failure.code, 1);
    assert!(
        failure.log_tail.iter().any(|l| l.contains("before")),
        "{:?}",
        failure.log_tail
    );
    assert!(
        !failure.log_tail.iter().any(|l| l.contains("after")),
        "{:?}",
        failure.log_tail
    );
    assert!(failure.log.ends_with("02-broken.log"));

    // Resumed without a terminal: tools is done earlier, broken fails again, asker would be skipped
    let mut recorder = Recorder::default();
    let outcome = Executor::new(config(&sb, false, true), &registry, &platform())
        .run(&run, &answers, &Interrupt::never(), &mut recorder)
        .unwrap();
    assert_eq!(outcome.status, RunStatus::Failed);
    assert_eq!(
        recorder.outcomes[0],
        ("tools".to_string(), StepOutcome::DoneEarlier)
    );
    assert!(recorder.events.iter().all(|e| e != "started tools"));
}

#[test]
fn attended_units_are_skipped_with_yes_and_a_dry_run_runs_nothing() {
    let sb = sandbox();
    fs::write(sb.repo.join("modules/demo/files/dark"), "").unwrap();
    fs::write(sb.repo.join("modules/demo/files/light"), "").unwrap();
    let registry = registry(&sb.repo);
    let store = RunStore::new(sb.dir.path().join("state"));
    let answers = Answers::from_selection(&registry, &Selection::new());

    let run = store.create(&new_run(&["asker"], &answers, false)).unwrap();
    let mut recorder = Recorder::default();
    let outcome = Executor::new(config(&sb, false, true), &registry, &platform())
        .run(&run, &answers, &Interrupt::never(), &mut recorder)
        .unwrap();
    assert_eq!(outcome.status, RunStatus::Completed);
    assert_eq!(outcome.skipped, 1);
    assert_eq!(run.status("asker"), Status::Skipped);
    assert!(matches!(recorder.outcomes[0].1, StepOutcome::Skipped(_)));

    let dry = store
        .create(&new_run(&["tools", "asker"], &answers, true))
        .unwrap();
    let outcome = Executor::new(config(&sb, true, false), &registry, &platform())
        .run(
            &dry,
            &answers,
            &Interrupt::never(),
            &mut Recorder::default(),
        )
        .unwrap();
    assert_eq!(outcome.status, RunStatus::Completed);
    assert_eq!(
        outcome.done, 2,
        "a dry run runs the attended units too, in the background"
    );
    assert!(
        !sb.fake_log.exists(),
        "no package or service tool was called"
    );
    assert!(!sb.home.join(".conf").exists() && !sb.home.join("greeted").exists());
    let log = fs::read_to_string(dry.step_log(1).unwrap()).unwrap();
    assert!(
        log.contains("dry run: not run") && log.contains("would link"),
        "{log}"
    );
}

#[test]
fn files_only_deploys_the_files_and_runs_the_hooks_but_installs_nothing() {
    let sb = sandbox();
    fs::write(sb.repo.join("modules/demo/files/dark"), "").unwrap();
    fs::write(sb.repo.join("modules/demo/files/light"), "").unwrap();
    let registry = registry(&sb.repo);
    let store = RunStore::new(sb.dir.path().join("state"));
    let mut selection = Selection::new();
    selection.set_variant("tools", "theme", "light");
    let answers = Answers::from_selection(&registry, &selection);
    let run = store
        .create(&NewRun {
            files_only: true,
            ..new_run(&["tools", "asker"], &answers, false)
        })
        .unwrap();
    assert!(!run.is_resumable(), "a files-only run is never resumed");
    let config = ExecConfig {
        files_only: true,
        ..config(&sb, false, true)
    };
    let mut recorder = Recorder::default();
    let outcome = Executor::new(config, &registry, &platform())
        .run(&run, &answers, &Interrupt::never(), &mut recorder)
        .unwrap();
    assert_eq!(
        outcome.status,
        RunStatus::Completed,
        "{:?}",
        recorder.outcomes
    );
    assert_eq!(
        (outcome.done, outcome.skipped),
        (1, 1),
        "the attended unit still needs the terminal"
    );
    assert!(!sb.fake_log.exists(), "no tool was called");
    assert_eq!(
        fs::read_link(sb.home.join(".theme")).unwrap(),
        sb.repo.join("modules/demo/files/light")
    );
    assert!(
        sb.home.join("greeted").exists(),
        "the hook ran after the files"
    );
    assert!(run.describe().contains("(files only)"));
}

#[test]
fn a_fragment_of_another_module_brings_its_files_and_hooks() {
    let sb = sandbox();
    fs::write(sb.repo.join("modules/demo/files/dark"), "").unwrap();
    fs::write(sb.repo.join("modules/demo/files/light"), "").unwrap();
    let extra = sb.repo.join("modules/extra");
    fs::create_dir_all(extra.join("files")).unwrap();
    fs::write(extra.join("files/extra.conf"), "extra\n").unwrap();
    fs::write(
        extra.join("hooks.sh"),
        "extra_hello() {\n    log_info \"extra for $INPUT_NAME\"\n    echo hi > \"$HOME/extra\"\n}\n",
    )
    .unwrap();
    let mut declarations = declarations(&sb.repo);
    declarations.modules.push(ModuleDeclaration {
        id: "extra".into(),
        name: "Extra".into(),
        about: None,
        root: extra.clone(),
        units: Vec::new(),
        fragments: vec![Fragment {
            unit: "tools".into(),
            merge: Merge::Extend,
            when: None,
            packages: Vec::new(),
            aur: Vec::new(),
            services: Vec::new(),
            files: vec![FileEntry {
                source: "files/extra.conf".into(),
                target: ".extra.conf".into(),
                mode: Mode::Copy,
                contents: false,
                backup: false,
                permissions: None,
            }],
            variants: Vec::new(),
            inputs: Vec::new(),
            hooks: vec![Hook {
                run: "extra_hello".into(),
                when: None,
            }],
        }],
    });
    let registry = Registry::new(declarations, &platform()).unwrap();
    let store = RunStore::new(sb.dir.path().join("state"));
    let mut selection = Selection::new();
    selection.set_input("tools", "name", model::InputValue::Text("x".into()));
    let answers = Answers::from_selection(&registry, &selection);
    let run = store.create(&new_run(&["tools"], &answers, false)).unwrap();
    let outcome = Executor::new(config(&sb, false, false), &registry, &platform())
        .run(
            &run,
            &answers,
            &Interrupt::never(),
            &mut Recorder::default(),
        )
        .unwrap();
    assert_eq!(outcome.status, RunStatus::Completed);
    assert_eq!(
        fs::read_to_string(sb.home.join(".extra.conf")).unwrap(),
        "extra\n",
        "the file of the fragment, from its own module"
    );
    assert_eq!(
        fs::read_to_string(sb.home.join("extra")).unwrap(),
        "hi\n",
        "the hook of the fragment, from its own hooks.sh"
    );
    assert!(
        sb.home.join("greeted").exists(),
        "the unit's own hook ran too"
    );
    let log = fs::read_to_string(run.step_log(1).unwrap()).unwrap();
    assert!(log.contains("modules/extra/hooks.sh extra_hello"), "{log}");
}

#[test]
fn an_option_a_fragment_adds_takes_its_file_from_the_fragment_module() {
    let sb = sandbox();
    fs::write(sb.repo.join("modules/demo/files/dark"), "").unwrap();
    fs::write(sb.repo.join("modules/demo/files/light"), "").unwrap();
    let extra = sb.repo.join("modules/extra");
    fs::create_dir_all(extra.join("files")).unwrap();
    fs::write(extra.join("files/work"), "work theme\n").unwrap();
    let mut declarations = declarations(&sb.repo);
    declarations.modules.push(ModuleDeclaration {
        id: "extra".into(),
        name: "Extra".into(),
        about: None,
        root: extra.clone(),
        units: Vec::new(),
        fragments: vec![Fragment {
            unit: "tools".into(),
            merge: Merge::Extend,
            when: None,
            packages: Vec::new(),
            aur: Vec::new(),
            services: Vec::new(),
            files: Vec::new(),
            variants: vec![model::Variant {
                id: "theme".into(),
                name: String::new(),
                options: vec!["work".into()],
                default: None,
            }],
            inputs: Vec::new(),
            hooks: Vec::new(),
        }],
    });
    let registry = Registry::new(declarations, &platform()).unwrap();
    let store = RunStore::new(sb.dir.path().join("state"));
    let mut selection = Selection::new();
    selection.set_input("tools", "name", model::InputValue::Text("x".into()));
    selection.set_variant("tools", "theme", "work");
    let answers = Answers::from_selection(&registry, &selection);
    let run = store.create(&new_run(&["tools"], &answers, false)).unwrap();
    let outcome = Executor::new(config(&sb, false, false), &registry, &platform())
        .run(
            &run,
            &answers,
            &Interrupt::never(),
            &mut Recorder::default(),
        )
        .unwrap();
    assert_eq!(outcome.status, RunStatus::Completed);
    assert_eq!(
        fs::read_link(sb.home.join(".theme")).unwrap(),
        extra.join("files/work"),
        "the option's file comes from the fragment's module"
    );
}
