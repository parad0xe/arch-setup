//! One run: its steps and their statuses, its variants and answers, its
//! logs.

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Local, TimeZone};

use crate::error::JournalError;

/// Where a step stands in a run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Pending,
    Started,
    Done,
    Failed,
    Skipped,
    Interrupted,
}

impl Status {
    pub fn as_str(self) -> &'static str {
        match self {
            Status::Pending => "pending",
            Status::Started => "started",
            Status::Done => "done",
            Status::Failed => "failed",
            Status::Skipped => "skipped",
            Status::Interrupted => "interrupted",
        }
    }

    pub fn parse(text: &str) -> Option<Status> {
        [
            Status::Pending,
            Status::Started,
            Status::Done,
            Status::Failed,
            Status::Skipped,
            Status::Interrupted,
        ]
        .into_iter()
        .find(|s| s.as_str() == text)
    }

    /// Nothing left to do for the step.
    pub fn is_finished(self) -> bool {
        matches!(self, Status::Done | Status::Skipped)
    }
}

/// A run: its folder and its steps, the unit ids in run order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Run {
    dir: PathBuf,
    steps: Vec<String>,
}

/// One line of the status file.
struct Entry {
    unit: String,
    status: Status,
    code: Option<i32>,
}

impl Run {
    /// Opens an existing run folder.
    pub fn open(dir: &Path) -> Result<Run, JournalError> {
        let plan = dir.join("plan");
        if !plan.is_file() {
            return Err(JournalError::NoPlan {
                path: dir.to_path_buf(),
            });
        }
        let steps = read(&plan)?
            .lines()
            .filter_map(|line| line.strip_prefix("unit "))
            .map(|id| id.trim().to_string())
            .filter(|id| !id.is_empty())
            .collect();
        Ok(Run {
            dir: dir.to_path_buf(),
            steps,
        })
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// The unit ids, in run order.
    pub fn steps(&self) -> &[String] {
        &self.steps
    }

    /// A value of the meta file.
    pub fn meta(&self, key: &str) -> Option<String> {
        let text = fs::read_to_string(self.dir.join("meta")).ok()?;
        text.lines()
            .find_map(|line| line.strip_prefix(&format!("{key}=")).map(str::to_string))
    }

    pub fn profile(&self) -> String {
        self.meta("profile").unwrap_or_else(|| "none".to_string())
    }

    pub fn is_dry_run(&self) -> bool {
        self.meta("dry_run").as_deref() == Some("1")
    }

    /// The source of the private repository the run used, when it had one.
    pub fn private(&self) -> Option<String> {
        self.meta("private").filter(|source| !source.is_empty())
    }

    pub fn started(&self) -> Option<DateTime<Local>> {
        let epoch: i64 = self.meta("started")?.parse().ok()?;
        Local.timestamp_opt(epoch, 0).single()
    }

    /// The variants of the run: (unit, variant, option).
    pub fn variants(&self) -> Vec<(String, String, String)> {
        triples(&self.dir.join("variants"))
    }

    /// The answers of the run: (unit, input, value).
    pub fn inputs(&self) -> Vec<(String, String, String)> {
        triples(&self.dir.join("inputs"))
    }

    /// Marks the run as left aside: it is not offered again.
    pub fn abandon(&self) -> Result<(), JournalError> {
        append(&self.dir.join("meta"), "abandoned=1\n")
    }

    /// Not a dry run, not abandoned, not complete.
    pub fn is_resumable(&self) -> bool {
        !self.is_dry_run()
            && !self.is_files_only()
            && self.meta("abandoned").as_deref() != Some("1")
            && !self.is_complete()
    }

    /// Only the files of its units were deployed.
    pub fn is_files_only(&self) -> bool {
        self.meta("files_only").as_deref() == Some("1")
    }

    fn entries(&self) -> Vec<Entry> {
        let text = fs::read_to_string(self.dir.join("status")).unwrap_or_default();
        text.lines()
            .filter_map(|line| {
                let mut words = line.split_whitespace();
                let _epoch = words.next()?;
                if words.next()? != "unit" {
                    return None;
                }
                let unit = words.next()?.to_string();
                let status = Status::parse(words.next()?)?;
                let code = words.next().and_then(|c| c.parse().ok());
                Some(Entry { unit, status, code })
            })
            .collect()
    }

    fn last_entry(&self, unit: &str) -> Option<Entry> {
        self.entries().into_iter().rev().find(|e| e.unit == unit)
    }

    /// The status of a step: the last one recorded, or pending.
    pub fn status(&self, unit: &str) -> Status {
        self.last_entry(unit)
            .map(|e| e.status)
            .unwrap_or(Status::Pending)
    }

    /// The exit code recorded with the last status of a step.
    pub fn code(&self, unit: &str) -> Option<i32> {
        self.last_entry(unit).and_then(|e| e.code)
    }

    /// Records the status of a step, with its exit code for a failure.
    pub fn record(
        &self,
        unit: &str,
        status: Status,
        code: Option<i32>,
    ) -> Result<(), JournalError> {
        let code = code.map(|c| format!(" {c}")).unwrap_or_default();
        append(
            &self.dir.join("status"),
            &format!(
                "{} unit {unit} {}{code}\n",
                Local::now().timestamp(),
                status.as_str()
            ),
        )
    }

    /// The log of a step, from its number in the run (from 1).
    pub fn step_log(&self, index: usize) -> Result<PathBuf, JournalError> {
        let unit =
            self.steps
                .get(index.wrapping_sub(1))
                .ok_or_else(|| JournalError::NoSuchStep {
                    path: self.dir.clone(),
                    index,
                    steps: self.steps.len(),
                })?;
        Ok(self
            .dir
            .join("steps")
            .join(format!("{index:02}-{unit}.log")))
    }

    /// What the setup printed during the run.
    pub fn setup_log(&self) -> PathBuf {
        self.dir.join("setup.log")
    }

    /// Every step done or skipped.
    pub fn is_complete(&self) -> bool {
        self.steps
            .iter()
            .all(|unit| self.status(unit).is_finished())
    }

    /// One line: when the run started, its profile, how many steps are done
    /// and where it stopped.
    pub fn describe(&self) -> String {
        let started = self
            .started()
            .map(|t| t.format("%Y-%m-%d %H:%M").to_string())
            .unwrap_or_else(|| "?".to_string());
        let finished = self
            .steps
            .iter()
            .filter(|unit| self.status(unit).is_finished())
            .count();
        let stopped = self
            .steps
            .iter()
            .find_map(|unit| match self.status(unit) {
                Status::Pending | Status::Done | Status::Skipped => None,
                status => Some(format!(", stopped at {unit} ({})", status.as_str())),
            })
            .unwrap_or_default();
        let files = if self.is_files_only() {
            " (files only)"
        } else {
            ""
        };
        format!(
            "run of {started}, profile {}{files}: {finished}/{} steps done{stopped}",
            self.profile(),
            self.steps.len()
        )
    }
}

/// The "<a> <b> <rest>" lines of a file; a missing file holds none.
fn triples(path: &Path) -> Vec<(String, String, String)> {
    fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .filter_map(|line| {
            let mut words = line.splitn(3, ' ');
            Some((
                words.next()?.to_string(),
                words.next()?.to_string(),
                words.next().unwrap_or_default().to_string(),
            ))
        })
        .collect()
}

pub(crate) fn read(path: &Path) -> Result<String, JournalError> {
    fs::read_to_string(path).map_err(|source| JournalError::Io {
        path: path.to_path_buf(),
        source,
    })
}

pub(crate) fn write(path: &Path, text: &str) -> Result<(), JournalError> {
    fs::write(path, text).map_err(|source| JournalError::Io {
        path: path.to_path_buf(),
        source,
    })
}

pub(crate) fn append(path: &Path, text: &str) -> Result<(), JournalError> {
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(|source| JournalError::Io {
            path: path.to_path_buf(),
            source,
        })?;
    file.write_all(text.as_bytes())
        .map_err(|source| JournalError::Io {
            path: path.to_path_buf(),
            source,
        })
}
