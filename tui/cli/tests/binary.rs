//! The binary from end to end, in a sandbox: a repository with the real
//! `lib/`, fake tools first on the PATH, a home, a state folder and a
//! profiles folder of its own. Nothing of the machine is touched.

use std::fs;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use nix::sys::signal::{Signal, kill};
use nix::unistd::Pid;

const PUBLIC_MANIFEST: &str = r#"
[module]
name = "Demo"
about = "A module for the tests"

[[unit]]
id = "tools"
name = "Tools"
packages = ["git"]
services = [{ name = "svc", now = true }]
files = [
  { source = "files/conf", target = ".conf", mode = "symlink" },
  { source = "files/{theme}", target = ".theme", mode = "symlink" },
]
variants = [{ id = "theme", name = "Theme", options = ["dark", "light"] }]
inputs = [{ id = "name", prompt = "Your name", required = true }]
hooks = ["greet"]

[[unit]]
id = "broken"
name = "Broken"
hooks = ["failing"]

[[unit]]
id = "slow"
name = "Slow"
hooks = ["sleeping"]
"#;

const PUBLIC_HOOKS: &str = r#"
greet() {
    log_info "Hello $INPUT_NAME with $VARIANT_THEME"
    echo "$INPUT_NAME" > "$HOME/greeted"
}

failing() {
    log_info "checking"
    [ -e "$HOME/fixed" ] || false
}

sleeping() {
    touch "$HOME/started"
    sleep 30
}
"#;

const PRIVATE_MANIFEST: &str = r#"
[module]
name = "Secret"

[[unit]]
id = "nas"
name = "NAS mount"
requires = ["tools"]
files = [{ source = "files/nas.cred", target = ".nas.cred", mode = "copy", permissions = "600" }]
hooks = ["mount_nas"]
"#;

const PRIVATE_HOOKS: &str = "mount_nas() {\n    echo mounted > \"$HOME/mounted\"\n}\n";

struct Sandbox {
    dir: tempfile::TempDir,
    repo: PathBuf,
    private: PathBuf,
    home: PathBuf,
    state: PathBuf,
    profiles: PathBuf,
    bin: PathBuf,
    fake_log: PathBuf,
}

impl Sandbox {
    fn new() -> Sandbox {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        let repo = root.join("repo");
        let private = root.join("private");
        let home = root.join("home");
        let state = root.join("state");
        let profiles = root.join("profiles");
        let bin = root.join("bin");
        let fake_log = root.join("fake.log");
        for folder in [
            repo.join("modules/demo/files"),
            repo.join("profiles"),
            private.join("modules/secret/files"),
            private.join("profiles"),
            home.clone(),
            profiles.clone(),
            bin.clone(),
        ] {
            fs::create_dir_all(folder).unwrap();
        }
        let real_lib =
            fs::canonicalize(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../lib")).unwrap();
        symlink(&real_lib, repo.join("lib")).unwrap();

        fs::write(repo.join("modules/demo/module.toml"), PUBLIC_MANIFEST).unwrap();
        fs::write(repo.join("modules/demo/hooks.sh"), PUBLIC_HOOKS).unwrap();
        fs::write(repo.join("modules/demo/files/conf"), "conf\n").unwrap();
        fs::write(repo.join("modules/demo/files/dark"), "dark\n").unwrap();
        fs::write(repo.join("modules/demo/files/light"), "light\n").unwrap();
        fs::write(
            repo.join("profiles/demo.toml"),
            "units = [\"tools\"]\n[variants]\n\"tools.theme\" = \"light\"\n[inputs]\n\"tools.name\" = \"world\"\n",
        )
        .unwrap();
        fs::write(
            repo.join("profiles/broken.toml"),
            "units = [\"tools\", \"broken\"]\n[inputs]\n\"tools.name\" = \"world\"\n",
        )
        .unwrap();
        fs::write(repo.join("profiles/noname.toml"), "units = [\"tools\"]\n").unwrap();
        fs::write(repo.join("profiles/slow.toml"), "units = [\"slow\"]\n").unwrap();

        fs::write(private.join("modules/secret/module.toml"), PRIVATE_MANIFEST).unwrap();
        fs::write(private.join("modules/secret/hooks.sh"), PRIVATE_HOOKS).unwrap();
        fs::write(
            private.join("modules/secret/files/nas.cred"),
            "user=me\npassword=x\n",
        )
        .unwrap();
        fs::write(
            private.join("profiles/home.toml"),
            "units = [\"nas\"]\n[inputs]\n\"tools.name\" = \"me\"\n",
        )
        .unwrap();

        // The tools: sudo runs its command, the package and service tools
        // log their calls, the network is reachable
        let script = |name: &str, body: &str| {
            let path = bin.join(name);
            fs::write(&path, format!("#!/bin/bash\n{body}\n")).unwrap();
            fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
        };
        script(
            "sudo",
            "while [ $# -gt 0 ] && [ \"${1:0:1}\" = - ]; do shift; done\n[ $# -eq 0 ] || exec \"$@\"",
        );
        for tool in ["pacman", "yay", "apt-get", "systemctl"] {
            script(
                tool,
                &format!("echo \"{tool} $*\" >> \"{}\"", fake_log.display()),
            );
        }
        script("curl", "exit 0");
        script("ping", "exit 0");
        // No pacman runs (the fake ones of the other tests would be found)
        script("pgrep", "exit 1");
        Sandbox {
            dir,
            repo,
            private,
            home,
            state,
            profiles,
            bin,
            fake_log,
        }
    }

    /// The binary with the sandbox as its world: no terminal, plain symbols,
    /// without the repository arguments.
    fn bare(&self) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_setup"));
        let path = format!(
            "{}:{}",
            self.bin.display(),
            std::env::var("PATH").unwrap_or_default()
        );
        command
            .env("HOME", &self.home)
            .env("SETUP_STATE_DIR", &self.state)
            .env("XDG_DATA_HOME", self.dir.path().join("data"))
            .env("SETUP_NO_TTY", "1")
            .env("PACMAN_LOCK", self.dir.path().join("no.lck"))
            .env("PATH", path)
            .env("TERM", "dumb")
            .env("NO_COLOR", "1")
            .env_remove("SETUP_DIR")
            .arg("--ascii")
            .stdin(Stdio::null());
        command
    }

    /// The binary on the repository and the profiles of the sandbox.
    fn command(&self) -> Command {
        let mut command = self.bare();
        command
            .arg("--repo")
            .arg(&self.repo)
            .arg("--profiles")
            .arg(&self.profiles);
        command
    }

    fn run(&self, args: &[&str]) -> Output {
        self.command().args(args).output().unwrap()
    }

    fn fake_calls(&self) -> String {
        fs::read_to_string(&self.fake_log).unwrap_or_default()
    }

    /// The folder of the latest run.
    fn latest_run(&self) -> PathBuf {
        fs::read_link(self.state.join("latest")).unwrap()
    }
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn code(output: &Output) -> i32 {
    output.status.code().unwrap_or(-1)
}

fn on_arch() -> bool {
    fs::read_to_string("/etc/os-release")
        .unwrap_or_default()
        .lines()
        .any(|line| line == "ID=arch" || line == "ID=archarm")
}

#[test]
fn a_profile_runs_installs_deploys_and_hooks_then_logs_shows_it() {
    let sb = Sandbox::new();
    let output = sb.run(&["profile", "demo", "--yes"]);
    let text = stdout(&output);
    assert_eq!(
        code(&output),
        0,
        "stdout:\n{text}\nstderr:\n{}",
        stderr(&output)
    );
    assert!(
        text.contains("Arch setup * 1 step * profile demo"),
        "{text}"
    );
    assert!(text.contains("Setup completed: 1/1 steps done"), "{text}");
    assert!(text.contains("Reboot to apply"), "{text}");

    let calls = sb.fake_calls();
    assert!(calls.contains(" git"), "the package is installed: {calls}");
    assert!(calls.contains("systemctl enable --now svc"), "{calls}");
    assert_eq!(
        fs::read_link(sb.home.join(".conf")).unwrap(),
        sb.repo.join("modules/demo/files/conf")
    );
    assert_eq!(
        fs::read_link(sb.home.join(".theme")).unwrap(),
        sb.repo.join("modules/demo/files/light"),
        "the variant of the profile"
    );
    assert_eq!(
        fs::read_to_string(sb.home.join("greeted")).unwrap(),
        "world\n"
    );

    let run = sb.latest_run();
    let log = fs::read_to_string(run.join("steps/01-tools.log")).unwrap();
    assert!(log.contains("[i] Hello world with light"), "{log}");
    assert!(
        fs::read_to_string(run.join("status"))
            .unwrap()
            .contains("unit tools done")
    );
    assert!(
        fs::read_to_string(run.join("setup.log"))
            .unwrap()
            .contains("Setup completed")
    );
    let meta = fs::read_to_string(run.join("meta")).unwrap();
    assert!(
        meta.contains("profile=demo") && meta.contains("profile demo --yes"),
        "{meta}"
    );
    assert!(!meta.contains("private="), "{meta}");

    let output = sb.run(&["logs"]);
    let text = stdout(&output);
    assert_eq!(code(&output), 0);
    assert!(text.contains("profile demo: 1/1 steps done"), "{text}");
    assert!(
        text.contains("done") && text.contains("steps/01-tools.log"),
        "{text}"
    );

    let output = sb.run(&["resume"]);
    assert_eq!(code(&output), 0);
    assert!(
        stdout(&output).contains("Nothing to resume"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn a_failing_hook_stops_the_run_and_resume_finishes_it_once_fixed() {
    let sb = Sandbox::new();
    let output = sb.run(&["profile", "broken", "--yes"]);
    let text = stdout(&output);
    assert_eq!(code(&output), 1, "{text}");
    assert!(text.contains("broken") && text.contains("failed"), "{text}");
    assert!(text.contains("Failed command: false"), "{text}");
    assert!(text.contains("Probable cause:"), "{text}");
    assert!(text.contains("To resume: setup resume"), "{text}");
    assert!(text.contains("Setup stopped: 1/2 steps done"), "{text}");
    let run = sb.latest_run();
    let status = fs::read_to_string(run.join("status")).unwrap();
    assert!(
        status.contains("unit tools done") && status.contains("unit broken failed 1"),
        "{status}"
    );

    // Resumed as is: tools is not run again, broken fails again
    let greeted_before = fs::metadata(sb.home.join("greeted"))
        .unwrap()
        .modified()
        .unwrap();
    let output = sb.run(&["resume", "--yes"]);
    let text = stdout(&output);
    assert_eq!(code(&output), 1, "{text}");
    assert!(text.contains("Resuming the run of"), "{text}");
    assert!(text.contains("done earlier"), "{text}");
    assert_eq!(
        fs::metadata(sb.home.join("greeted"))
            .unwrap()
            .modified()
            .unwrap(),
        greeted_before,
        "a step done earlier is not run again"
    );
    assert_eq!(sb.latest_run(), run, "the same run is resumed");

    // Fixed: the resume completes the run
    fs::write(sb.home.join("fixed"), "").unwrap();
    let output = sb.run(&["resume", "--yes"]);
    let text = stdout(&output);
    assert_eq!(code(&output), 0, "{text}");
    assert!(text.contains("Setup completed: 2/2 steps done"), "{text}");
    let log = fs::read_to_string(run.join("steps/02-broken.log")).unwrap();
    assert_eq!(
        log.matches("[i] checking").count(),
        3,
        "every attempt is in the log:\n{log}"
    );
    assert!(stdout(&sb.run(&["resume"])).contains("Nothing to resume"));
}

#[test]
fn a_dry_run_changes_nothing_and_is_not_resumed() {
    let sb = Sandbox::new();
    let output = sb.run(&["profile", "demo", "--dry-run", "--yes"]);
    let text = stdout(&output);
    assert_eq!(code(&output), 0, "{text}\n{}", stderr(&output));
    assert!(text.contains("profile demo * dry run"), "{text}");
    assert!(
        text.contains("Dry run finished: 1/1 steps done") && text.contains("Nothing was changed"),
        "{text}"
    );
    assert!(!sb.fake_log.exists(), "no tool was called");
    assert!(!sb.home.join(".conf").exists() && !sb.home.join("greeted").exists());
    assert!(
        !sb.state.join("latest").exists(),
        "a dry run is never the latest run"
    );
    assert!(stdout(&sb.run(&["logs"])).contains("No run yet"));
    assert!(stdout(&sb.run(&["resume"])).contains("Nothing to resume"));
}

#[test]
fn a_required_answer_missing_without_a_terminal_is_refused() {
    let sb = Sandbox::new();
    let output = sb.run(&["profile", "noname", "--yes"]);
    let error = stderr(&output);
    assert_eq!(code(&output), 1, "{error}");
    assert!(
        error.contains("tools: the answer name is required"),
        "{error}"
    );
    assert!(
        error.contains("\"tools.name\""),
        "the fix names the profile key: {error}"
    );
    assert!(!sb.fake_log.exists(), "nothing ran");
}

#[test]
fn mistakes_are_reported_with_the_right_exit_codes() {
    let sb = Sandbox::new();
    let output = sb.run(&["--help"]);
    assert_eq!(code(&output), 0);
    assert!(stdout(&output).contains("profile") && stdout(&output).contains("--dry-run"));

    for args in [
        &["resume", "--dry-run"][..],
        &["--yes"],
        &["logs", "--yes"],
        &["--bogus"],
        &["profile"],
    ] {
        let output = sb.run(args);
        assert_eq!(code(&output), 2, "{args:?}: {}", stderr(&output));
    }

    let output = sb.run(&["profile", "nope", "--yes"]);
    assert_eq!(code(&output), 1, "{}", stderr(&output));
    let error = stderr(&output);
    assert!(
        error.contains("unknown profile nope") && error.contains("demo"),
        "{error}"
    );

    let output = sb
        .bare()
        .args(["--repo", "/nonexistent", "dump"])
        .output()
        .unwrap();
    assert_eq!(code(&output), 1, "{}", stderr(&output));
    assert!(
        stderr(&output).contains("no setup repository found"),
        "{}",
        stderr(&output)
    );

    let output = sb.run(&[
        "--private",
        "git@host:me/private.git",
        "profile",
        "demo",
        "--yes",
    ]);
    assert_eq!(code(&output), 1);
    assert!(stderr(&output).contains("SSH URL"), "{}", stderr(&output));
    let output = sb.run(&["--private", "/nonexistent/usb", "profile", "demo", "--yes"]);
    assert_eq!(code(&output), 1);
    assert!(
        stderr(&output).contains("not a folder nor an HTTPS URL"),
        "{}",
        stderr(&output)
    );
}

#[test]
fn dump_describes_the_setup_as_json() {
    let sb = Sandbox::new();
    let output = sb.run(&["dump"]);
    assert_eq!(code(&output), 0, "{}", stderr(&output));
    let json: serde_json::Value = serde_json::from_str(&stdout(&output)).unwrap();
    assert!(json["platform"]["arch"].is_string());
    assert_eq!(
        json["repositories"]["public"],
        serde_json::json!(fs::canonicalize(&sb.repo).unwrap())
    );
    assert!(json["repositories"]["private"].is_null());
    let units: Vec<&str> = json["modules"][0]["units"]
        .as_array()
        .unwrap()
        .iter()
        .map(|u| u["id"].as_str().unwrap())
        .collect();
    assert_eq!(units, ["tools", "broken", "slow"]);
    assert_eq!(
        json["modules"][0]["units"][0]["variants"][0]["options"],
        serde_json::json!(["dark", "light"])
    );
    assert_eq!(
        json["modules"][0]["units"][0]["inputs"][0]["required"],
        serde_json::json!(true)
    );
    let profiles: Vec<&str> = json["profiles"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["name"].as_str().unwrap())
        .collect();
    assert_eq!(profiles, ["broken", "demo", "noname", "slow"]);
}

#[test]
fn a_private_folder_adds_its_units_and_is_remembered() {
    let sb = Sandbox::new();
    let private = sb.private.to_str().unwrap();
    let output = sb.run(&["--private", private, "profile", "home", "--yes"]);
    let text = stdout(&output);
    assert_eq!(code(&output), 0, "{text}\n{}", stderr(&output));
    assert!(
        text.contains("2 steps * profile home"),
        "tools is required by nas: {text}"
    );
    assert!(text.contains("Setup completed: 2/2 steps done"), "{text}");
    let cred = sb.home.join(".nas.cred");
    assert_eq!(fs::read_to_string(&cred).unwrap(), "user=me\npassword=x\n");
    assert_eq!(
        fs::metadata(&cred).unwrap().permissions().mode() & 0o777,
        0o600
    );
    assert!(sb.home.join("mounted").exists());
    let meta = fs::read_to_string(sb.latest_run().join("meta")).unwrap();
    assert!(meta.contains(&format!("private={private}")), "{meta}");
    assert!(stdout(&sb.run(&["logs"])).contains("Private repository:"));

    // Remembered: the next launch has the private units without --private
    let source = sb.dir.path().join("data/arch-setup/private.source");
    assert_eq!(fs::read_to_string(&source).unwrap().trim(), private);
    let output = sb.run(&["dump"]);
    assert_eq!(code(&output), 0, "{}", stderr(&output));
    let json: serde_json::Value = serde_json::from_str(&stdout(&output)).unwrap();
    assert_eq!(
        json["repositories"]["private"],
        serde_json::json!(fs::canonicalize(&sb.private).unwrap())
    );
    assert!(
        json["modules"]
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m["id"] == "secret")
    );

    // Gone: a warning, and the public setup alone
    fs::remove_dir_all(&sb.private).unwrap();
    let output = sb.run(&["dump"]);
    assert_eq!(code(&output), 0, "{}", stderr(&output));
    assert!(
        stdout(&output).contains("is not there any more"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn a_stale_pacman_lock_blocks_a_real_run_and_only_warns_a_dry_run() {
    if !on_arch() {
        // The lock is pacman's: the check runs on Arch Linux only
        return;
    }
    let sb = Sandbox::new();
    let lock = sb.dir.path().join("db.lck");
    fs::write(&lock, "").unwrap();
    let output = sb
        .command()
        .env("PACMAN_LOCK", &lock)
        .args(["profile", "demo", "--yes"])
        .output()
        .unwrap();
    let text = stdout(&output);
    assert_eq!(code(&output), 1, "{text}");
    assert!(
        text.contains("The setup cannot run on this machine:"),
        "{text}"
    );
    assert!(
        text.contains("A pacman lock remains") && text.contains("sudo rm"),
        "{text}"
    );
    assert!(!sb.fake_log.exists(), "nothing ran");

    let output = sb
        .command()
        .env("PACMAN_LOCK", &lock)
        .args(["profile", "demo", "--yes", "--dry-run"])
        .output()
        .unwrap();
    let text = stdout(&output);
    assert_eq!(code(&output), 0, "{text}");
    assert!(text.contains("ignored for the dry run"), "{text}");
    assert!(text.contains("Dry run finished"), "{text}");
}

#[test]
fn ctrl_c_stops_the_step_and_the_run_can_be_resumed() {
    let sb = Sandbox::new();
    let mut child = sb
        .command()
        .args(["profile", "slow", "--yes"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let started = sb.home.join("started");
    let deadline = Instant::now() + Duration::from_secs(20);
    while !started.exists() {
        assert!(Instant::now() < deadline, "the hook never started");
        if let Some(status) = child.try_wait().unwrap() {
            panic!("the setup ended before the hook started: {status}");
        }
        thread::sleep(Duration::from_millis(50));
    }
    kill(Pid::from_raw(child.id() as i32), Signal::SIGINT).unwrap();
    let deadline = Instant::now() + Duration::from_secs(20);
    while child.try_wait().unwrap().is_none() {
        if Instant::now() > deadline {
            child.kill().unwrap();
            panic!("the setup did not stop after Ctrl-C");
        }
        thread::sleep(Duration::from_millis(50));
    }
    let output = child.wait_with_output().unwrap();
    let text = stdout(&output);
    assert_eq!(code(&output), 130, "{text}\n{}", stderr(&output));
    assert!(text.contains("Interrupted during step 1/1 slow"), "{text}");
    assert!(text.contains("Setup interrupted: 0/1 steps done"), "{text}");
    let status = fs::read_to_string(sb.latest_run().join("status")).unwrap();
    assert!(status.contains("unit slow interrupted"), "{status}");
    let output = sb.run(&["logs"]);
    assert!(
        stdout(&output).contains("stopped at slow (interrupted)"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn new_creates_a_repository_the_setup_reads() {
    let sb = Sandbox::new();
    let mine = sb.dir.path().join("mine");
    let output = sb.run(&["new", mine.to_str().unwrap()]);
    assert_eq!(code(&output), 0, "{}\n{}", stdout(&output), stderr(&output));
    assert!(
        stdout(&output).contains("Created a private repository"),
        "{}",
        stdout(&output)
    );
    for file in [
        "modules/example/module.toml",
        "modules/example/hooks.sh",
        "modules/example/files/example.conf",
        "profiles/example.toml",
        "README.md",
    ] {
        assert!(mine.join(file).is_file(), "{file}");
    }
    assert!(
        !mine.join("lib").exists(),
        "a private repository has no hook library"
    );
    if Command::new("git")
        .arg("--version")
        .stdout(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
    {
        assert!(mine.join(".git").is_dir(), "git is started");
    }

    // As a private repository, its unit and its profile are there
    let output = sb.run(&["--private", mine.to_str().unwrap(), "dump"]);
    assert_eq!(code(&output), 0, "{}", stderr(&output));
    let json: serde_json::Value = serde_json::from_str(&stdout(&output)).unwrap();
    assert!(
        json["modules"]
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m["id"] == "example")
    );
    assert!(
        json["profiles"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["name"] == "example")
    );

    // A folder in use is refused
    let output = sb.run(&["new", mine.to_str().unwrap()]);
    assert_eq!(code(&output), 1);
    assert!(stderr(&output).contains("not empty"), "{}", stderr(&output));

    // Public: the hook library comes along and the repository stands alone
    // (a fresh sandbox: the first one remembers its private repository)
    let sb = Sandbox::new();
    let public = sb.dir.path().join("public");
    let output = sb.run(&["new", "--public", public.to_str().unwrap()]);
    assert_eq!(code(&output), 0, "{}\n{}", stdout(&output), stderr(&output));
    assert!(public.join("lib/hook.sh").is_file() && public.join("lib/platform.sh").is_file());
    let output = sb
        .bare()
        .args(["--repo", public.to_str().unwrap(), "dump"])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0, "{}", stderr(&output));
    let json: serde_json::Value = serde_json::from_str(&stdout(&output)).unwrap();
    assert_eq!(json["modules"][0]["id"], "example");
}

#[test]
fn files_only_deploys_the_configs_without_installing_or_checking() {
    let sb = Sandbox::new();
    // No --yes and no terminal: the checks would refuse; the files alone need none
    let output = sb.run(&["--files-only", "profile", "demo"]);
    let text = stdout(&output);
    assert_eq!(code(&output), 0, "{text}\n{}", stderr(&output));
    assert!(text.contains("profile demo * files only"), "{text}");
    assert!(text.contains("Files deployed: 1/1 steps done"), "{text}");
    assert!(
        !sb.fake_log.exists(),
        "no package or service tool was called"
    );
    assert_eq!(
        fs::read_link(sb.home.join(".theme")).unwrap(),
        sb.repo.join("modules/demo/files/light"),
        "the variant of the profile"
    );
    assert_eq!(
        fs::read_to_string(sb.home.join("greeted")).unwrap(),
        "world\n",
        "the hook ran with the answer of the profile"
    );
    assert!(stdout(&sb.run(&["logs"])).contains("(files only)"));
    assert!(stdout(&sb.run(&["resume"])).contains("Nothing to resume"));
    assert_eq!(code(&sb.run(&["resume", "--files-only"])), 2);
}

#[test]
fn config_refuses_unknown_units_and_the_commands_without_screens() {
    let sb = Sandbox::new();
    let output = sb.run(&["--config", "nope"]);
    assert_eq!(code(&output), 1, "{}", stderr(&output));
    assert!(
        stderr(&output).contains("unknown unit nope"),
        "{}",
        stderr(&output)
    );
    let output = sb.run(&["profile", "demo", "--config", "tools"]);
    assert_eq!(code(&output), 2);
}

#[test]
fn windows_is_sent_away() {
    let sb = Sandbox::new();
    let output = sb.bare().arg("--windows").output().unwrap();
    assert_eq!(code(&output), 1);
    let text = stdout(&output);
    assert!(text.contains("W I N D O W S ?   N O ."), "{text}");
    assert!(text.contains("go get lost somewhere else"), "{text}");
    assert!(
        text.lines().filter(|l| l.starts_with("  |")).count() == 7,
        "a frame:\n{text}"
    );
}
