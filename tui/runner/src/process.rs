//! A command of a step: its output in the log (shown too, in the
//! foreground), its last message, and a clean stop on Ctrl-C.

use std::fs::{self, OpenOptions};
use std::io::{self, BufRead, BufReader, Write};
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use nix::sys::signal::{self, Signal};
use nix::unistd::Pid;

use crate::commands::PACKAGE_TOOLS;
use crate::contract;
use crate::error::RunnerError;
use crate::interrupt::Interrupt;

/// How often a running command is looked at, and how long it gets to stop
/// by itself after each signal.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Timing {
    pub poll: Duration,
    pub grace: Duration,
}

impl Default for Timing {
    fn default() -> Timing {
        Timing {
            poll: Duration::from_millis(100),
            grace: Duration::from_secs(3),
        }
    }
}

/// A command running.
pub(crate) struct Running {
    child: Child,
    program: String,
    status_file: Option<PathBuf>,
    /// The lines of a foreground command, copied to the log by a thread.
    lines: Option<Receiver<String>>,
    tee: Option<JoinHandle<()>>,
    detached: bool,
    started: Instant,
    timing: Timing,
}

/// Starts a command with its output appended to the log. In the foreground,
/// the output is also handed back line by line and stdin is the
/// terminal's; in the background, stdin is empty and `status_file` receives
/// the last message of a hook.
pub(crate) fn spawn(
    mut command: Command,
    log: &Path,
    foreground: bool,
    status_file: Option<PathBuf>,
    timing: Timing,
) -> Result<Running, RunnerError> {
    let program = command.get_program().to_string_lossy().into_owned();
    let log_file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(log)
        .map_err(|source| RunnerError::Io {
            path: log.to_path_buf(),
            source,
        })?;
    let mut lines = None;
    let mut tee = None;
    if foreground {
        let (reader, writer) = io::pipe().map_err(|source| RunnerError::Spawn {
            program: program.clone(),
            source,
        })?;
        let writer_err = writer.try_clone().map_err(|source| RunnerError::Spawn {
            program: program.clone(),
            source,
        })?;
        command
            .stdin(Stdio::inherit())
            .stdout(writer)
            .stderr(writer_err);
        let (sender, receiver) = mpsc::channel();
        let mut log_file = log_file;
        tee = Some(thread::spawn(move || {
            let mut reader = BufReader::new(reader);
            let mut line = Vec::new();
            while let Ok(n) = reader.read_until(b'\n', &mut line) {
                if n == 0 {
                    break;
                }
                let _ = log_file.write_all(&line);
                let text = String::from_utf8_lossy(&line)
                    .trim_end_matches(['\n', '\r'])
                    .to_string();
                if sender.send(text).is_err() {
                    break;
                }
                line.clear();
            }
        }));
        lines = Some(receiver);
    } else {
        if let Some(status) = &status_file {
            command
                .env(contract::STEP_STATUS, status)
                .env(contract::QUIET, "1");
        }
        let log_err = log_file.try_clone().map_err(|source| RunnerError::Io {
            path: log.to_path_buf(),
            source,
        })?;
        command
            .stdin(Stdio::null())
            .stdout(log_file)
            .stderr(log_err);
    }
    let child = command.spawn().map_err(|source| RunnerError::Spawn {
        program: program.clone(),
        source,
    })?;
    Ok(Running {
        child,
        program,
        status_file,
        lines,
        tee,
        detached: false,
        started: Instant::now(),
        timing,
    })
}

impl Running {
    pub(crate) fn elapsed(&self) -> Duration {
        self.started.elapsed()
    }

    /// The last message of a background hook.
    pub(crate) fn message(&self) -> Option<String> {
        let text = fs::read_to_string(self.status_file.as_ref()?).ok()?;
        text.lines()
            .next()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .map(str::to_string)
    }

    /// The lines a foreground command printed since the last call.
    pub(crate) fn drain_lines(&self) -> Vec<String> {
        match &self.lines {
            Some(receiver) => receiver.try_iter().collect(),
            None => Vec::new(),
        }
    }

    fn join_tee(&mut self) {
        if let Some(tee) = self.tee.take() {
            let _ = tee.join();
        }
    }

    /// The exit code once the command has finished.
    pub(crate) fn poll(&mut self) -> Result<Option<i32>, RunnerError> {
        let status = self.child.try_wait().map_err(|source| RunnerError::Spawn {
            program: self.program.clone(),
            source,
        })?;
        if status.is_some() {
            self.join_tee();
        }
        Ok(status.map(exit_code))
    }

    pub(crate) fn wait(&mut self) -> Result<i32, RunnerError> {
        let status = self.child.wait().map_err(|source| RunnerError::Spawn {
            program: self.program.clone(),
            source,
        })?;
        self.join_tee();
        Ok(exit_code(status))
    }

    fn wait_for(&mut self, duration: Duration) -> Result<bool, RunnerError> {
        let deadline = Instant::now() + duration;
        loop {
            if self.poll()?.is_some() {
                return Ok(true);
            }
            if Instant::now() >= deadline {
                return Ok(false);
            }
            thread::sleep(self.timing.poll);
        }
    }

    /// Stops the command after an interruption: a few seconds to stop by
    /// itself (Ctrl-C reached it too), then an interrupt, a wait for a
    /// package tool to finish its current package (another Ctrl-C leaves
    /// it running), then a termination and a kill of what remains.
    pub(crate) fn stop(
        &mut self,
        interrupt: &Interrupt,
        mut waiting: impl FnMut(&str),
    ) -> Result<i32, RunnerError> {
        let pid = self.child.id() as i32;
        let interrupts = interrupt.count();
        for sig in [
            None,
            Some(Signal::SIGINT),
            Some(Signal::SIGTERM),
            Some(Signal::SIGKILL),
        ] {
            if let Some(sig) = sig {
                kill_tree(pid, sig);
            }
            if self.wait_for(self.timing.grace)? {
                break;
            }
            if sig == Some(Signal::SIGINT) {
                while let Some(tool) = busy_tool(pid) {
                    if interrupt.count() > interrupts {
                        self.detached = true;
                        return Ok(contract::INTERRUPTED);
                    }
                    waiting(&tool);
                    if self.wait_for(Duration::from_secs(1))? {
                        break;
                    }
                }
                if self.poll()?.is_some() {
                    break;
                }
            }
        }
        self.wait()
    }
}

/// A command still running when dropped (the runner stops on an error of
/// its own) is interrupted, then terminated.
impl Drop for Running {
    fn drop(&mut self) {
        if !self.detached && self.child.try_wait().ok().flatten().is_none() {
            let pid = self.child.id() as i32;
            kill_tree(pid, Signal::SIGINT);
            let _ = self.wait_for(Duration::from_secs(1));
            kill_tree(pid, Signal::SIGTERM);
            let _ = self.child.wait();
            self.join_tee();
        }
        if let Some(file) = &self.status_file {
            let _ = fs::remove_file(file);
        }
    }
}

/// The exit code of a finished process: 128 + the signal when one ended it.
fn exit_code(status: ExitStatus) -> i32 {
    status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(0))
}

/// Every process: pid, parent pid and command name, from /proc.
fn processes() -> Vec<(i32, i32, String)> {
    let Ok(entries) = fs::read_dir("/proc") else {
        return Vec::new();
    };
    entries
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            let pid: i32 = e.file_name().to_str()?.parse().ok()?;
            let stat = fs::read_to_string(e.path().join("stat")).ok()?;
            // "pid (comm) state ppid ...": the comm may hold spaces
            let (_, rest) = stat.split_once('(')?;
            let (comm, rest) = rest.rsplit_once(')')?;
            let ppid: i32 = rest.split_whitespace().nth(1)?.parse().ok()?;
            Some((pid, ppid, comm.to_string()))
        })
        .collect()
}

/// The descendants of a process, the deepest first, with their names.
fn descendants(pid: i32) -> Vec<(i32, String)> {
    fn collect(pid: i32, all: &[(i32, i32, String)], out: &mut Vec<(i32, String)>) {
        for (child, _, comm) in all.iter().filter(|(_, ppid, _)| *ppid == pid) {
            collect(*child, all, out);
            out.push((*child, comm.clone()));
        }
    }
    let all = processes();
    let mut out = Vec::new();
    collect(pid, &all, &mut out);
    out
}

/// A package tool running under a process, if any.
fn busy_tool(pid: i32) -> Option<String> {
    descendants(pid)
        .into_iter()
        .map(|(_, comm)| comm)
        .find(|comm| PACKAGE_TOOLS.contains(&comm.as_str()))
}

/// Sends a signal to a process and its descendants, the deepest first (so
/// that sudo sees its command end before it is signalled itself). A process
/// gone meanwhile is no error.
pub(crate) fn kill_tree(pid: i32, sig: Signal) {
    for (child, _) in descendants(pid) {
        let _ = signal::kill(Pid::from_raw(child), sig);
    }
    let _ = signal::kill(Pid::from_raw(pid), sig);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fast() -> Timing {
        Timing {
            poll: Duration::from_millis(20),
            grace: Duration::from_millis(300),
        }
    }

    #[test]
    fn a_background_command_logs_its_output_and_its_last_message() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("step.log");
        let status = log.with_extension("status");
        let mut command = Command::new("bash");
        command.args([
            "-c",
            "echo out; echo 'Installing: foo' > \"$SETUP_STEP_STATUS\"; echo err >&2; exit 3",
        ]);
        let mut running = spawn(command, &log, false, Some(status.clone()), fast()).unwrap();
        assert_eq!(running.wait().unwrap(), 3);
        assert_eq!(running.message().as_deref(), Some("Installing: foo"));
        let text = fs::read_to_string(&log).unwrap();
        assert!(text.contains("out") && text.contains("err"), "{text}");
        drop(running);
        assert!(!status.exists(), "the status file is removed");
    }

    #[test]
    fn a_foreground_command_hands_its_lines_back() {
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("step.log");
        let mut command = Command::new("bash");
        command.args(["-c", "echo hello; echo world"]);
        let mut running = spawn(command, &log, true, None, fast()).unwrap();
        let code = loop {
            if let Some(code) = running.poll().unwrap() {
                break code;
            }
            thread::sleep(Duration::from_millis(20));
        };
        assert_eq!(code, 0);
        assert_eq!(running.drain_lines(), ["hello", "world"]);
        assert_eq!(fs::read_to_string(&log).unwrap(), "hello\nworld\n");
    }

    #[test]
    fn a_stuck_command_is_stopped_by_escalating_signals() {
        let dir = tempfile::tempdir().unwrap();
        let mut command = Command::new("bash");
        command.args(["-c", "trap '' INT; sleep 30"]);
        let mut running =
            spawn(command, &dir.path().join("step.log"), false, None, fast()).unwrap();
        thread::sleep(Duration::from_millis(200));
        let interrupt = Interrupt::never();
        interrupt.raise();
        let mut waited = Vec::new();
        let code = running
            .stop(&interrupt, |tool| waited.push(tool.to_string()))
            .unwrap();
        assert!(
            code == 128 + Signal::SIGTERM as i32 || code == contract::INTERRUPTED,
            "ended by a signal: {code}"
        );
        assert!(waited.is_empty(), "sleep is no package tool");
    }

    #[test]
    fn a_package_tool_is_waited_for_and_a_second_interrupt_leaves_it_running() {
        let dir = tempfile::tempdir().unwrap();
        // A copy of sleep named pacman: the name is what is looked at
        let pacman = dir.path().join("pacman");
        fs::copy("/usr/bin/sleep", &pacman).unwrap();
        // A script, not bash -c: bash would exec its last command, and the
        // tool would be the process itself instead of a descendant
        let script = dir.path().join("step.sh");
        fs::write(
            &script,
            format!("trap '' INT\n\"{}\" 30\n", pacman.display()),
        )
        .unwrap();
        let mut command = Command::new("bash");
        command.arg(&script);
        let mut running =
            spawn(command, &dir.path().join("step.log"), false, None, fast()).unwrap();
        thread::sleep(Duration::from_millis(300));
        let interrupt = Interrupt::never();
        interrupt.raise();
        let second = interrupt.clone();
        let mut waited = Vec::new();
        let code = running
            .stop(&interrupt, |tool| {
                waited.push(tool.to_string());
                second.raise();
            })
            .unwrap();
        assert_eq!(code, contract::INTERRUPTED);
        assert_eq!(waited, ["pacman"]);
        let pid = running.child.id() as i32;
        drop(running);
        assert!(
            fs::read_to_string(format!("/proc/{pid}/stat"))
                .map(|s| !s.contains(") Z "))
                .unwrap_or(false),
            "left running"
        );
        kill_tree(pid, Signal::SIGKILL);
    }
}
