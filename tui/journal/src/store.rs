//! The folder of the runs: creating one, finding the latest or the one to
//! resume, pruning the old ones.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::Local;

use crate::error::JournalError;
use crate::run::{Run, write};

/// How many finished runs `prune` keeps by default.
pub const RUNS_KEPT: usize = 10;

/// What a new run records.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NewRun {
    pub profile: String,
    /// The unit ids, in run order.
    pub steps: Vec<String>,
    /// (unit, variant, option)
    pub variants: Vec<(String, String, String)>,
    /// (unit, input, value), the secrets left out.
    pub inputs: Vec<(String, String, String)>,
    /// Never resumed, never the latest run.
    pub dry_run: bool,
    /// The architecture, for the record.
    pub machine: String,
    /// The command line, for the record.
    pub argv: String,
    /// The private repository in use (its source), for a resume.
    pub private: Option<String>,
    /// Only the files of the units are deployed: never resumed.
    pub files_only: bool,
}

/// The runs under a state folder.
#[derive(Debug, Clone)]
pub struct RunStore {
    state_dir: PathBuf,
}

impl RunStore {
    pub fn new(state_dir: impl Into<PathBuf>) -> RunStore {
        RunStore {
            state_dir: state_dir.into(),
        }
    }

    /// The folder of the runs.
    pub fn runs_dir(&self) -> PathBuf {
        self.state_dir.join("runs")
    }

    /// The link to the latest run.
    pub fn latest_link(&self) -> PathBuf {
        self.state_dir.join("latest")
    }

    /// Creates the folder of a new run and makes it the latest (not for a
    /// dry run).
    pub fn create(&self, new: &NewRun) -> Result<Run, JournalError> {
        let runs = self.runs_dir();
        fs::create_dir_all(&runs).map_err(|source| JournalError::Io {
            path: runs.clone(),
            source,
        })?;
        let name = Local::now().format("%Y-%m-%d_%H%M%S").to_string();
        let mut dir = runs.join(&name);
        let mut n = 2;
        while dir.exists() {
            dir = runs.join(format!("{name}.{n}"));
            n += 1;
        }
        let steps_dir = dir.join("steps");
        fs::create_dir_all(&steps_dir).map_err(|source| JournalError::Io {
            path: steps_dir,
            source,
        })?;

        let private = new
            .private
            .as_ref()
            .map(|source| format!("private={source}\n"))
            .unwrap_or_default();
        write(
            &dir.join("meta"),
            &format!(
                "profile={}\nstarted={}\ndry_run={}\nfiles_only={}\nmachine={}\nargv={}\n{private}",
                new.profile,
                Local::now().timestamp(),
                u8::from(new.dry_run),
                u8::from(new.files_only),
                new.machine,
                new.argv
            ),
        )?;
        write(
            &dir.join("plan"),
            &new.steps
                .iter()
                .map(|id| format!("unit {id}\n"))
                .collect::<String>(),
        )?;
        write(&dir.join("variants"), &lines(&new.variants))?;
        write(&dir.join("inputs"), &lines(&new.inputs))?;
        write(&dir.join("status"), "")?;

        if !new.dry_run {
            let link = self.latest_link();
            if link.symlink_metadata().is_ok() {
                fs::remove_file(&link).map_err(|source| JournalError::Io {
                    path: link.clone(),
                    source,
                })?;
            }
            std::os::unix::fs::symlink(&dir, &link)
                .map_err(|source| JournalError::Io { path: link, source })?;
        }
        Run::open(&dir)
    }

    /// The run folders, the newest first (their names are dates, with a .2,
    /// .3... suffix for the runs started the same second).
    pub fn all(&self) -> Result<Vec<Run>, JournalError> {
        let runs = self.runs_dir();
        let Ok(entries) = fs::read_dir(&runs) else {
            return Ok(Vec::new());
        };
        let mut dirs: Vec<PathBuf> = entries
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.join("plan").is_file())
            .collect();
        dirs.sort_by_key(|dir| std::cmp::Reverse(order_key(dir)));
        dirs.iter().map(|dir| Run::open(dir)).collect()
    }

    /// The latest run that was not a dry run.
    pub fn latest(&self) -> Result<Option<Run>, JournalError> {
        Ok(self.all()?.into_iter().find(|run| !run.is_dry_run()))
    }

    /// The newest run that can be resumed.
    pub fn resumable(&self) -> Result<Option<Run>, JournalError> {
        Ok(self.all()?.into_iter().find(Run::is_resumable))
    }

    /// Removes the oldest runs, keeping the newest `keep` and the ones that
    /// can still be resumed.
    pub fn prune(&self, keep: usize) -> Result<(), JournalError> {
        let mut kept = 0;
        for run in self.all()? {
            if run.is_resumable() {
                continue;
            }
            kept += 1;
            if kept > keep {
                fs::remove_dir_all(run.dir()).map_err(|source| JournalError::Io {
                    path: run.dir().to_path_buf(),
                    source,
                })?;
            }
        }
        Ok(())
    }
}

fn lines(triples: &[(String, String, String)]) -> String {
    triples
        .iter()
        .map(|(a, b, c)| format!("{a} {b} {c}\n"))
        .collect()
}

/// The date part and the collision suffix of a run folder name.
fn order_key(dir: &Path) -> (String, u32) {
    let name = dir
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .into_owned();
    match name.split_once('.') {
        Some((base, n)) => (base.to_string(), n.parse().unwrap_or(1)),
        None => (name, 1),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::run::Status;

    fn new_run(profile: &str, dry_run: bool) -> NewRun {
        NewRun {
            profile: profile.into(),
            steps: vec!["system".into(), "shell".into(), "git".into()],
            variants: vec![("shell".into(), "zshrc".into(), "mine".into())],
            inputs: vec![("git".into(), "name".into(), "me".into())],
            dry_run,
            machine: "x86_64".into(),
            argv: "-p demo".into(),
            private: Some("/media/usb/private".into()),
            files_only: false,
        }
    }

    #[test]
    fn a_run_records_its_steps_and_is_resumed_until_complete() {
        let state = tempfile::tempdir().unwrap();
        let store = RunStore::new(state.path());
        let run = store.create(&new_run("demo", false)).unwrap();
        assert!(run.dir().join("steps").is_dir());
        assert_eq!(
            fs::read_to_string(run.dir().join("plan")).unwrap(),
            "unit system\nunit shell\nunit git\n"
        );
        assert_eq!(
            run.variants(),
            [("shell".to_string(), "zshrc".to_string(), "mine".to_string())]
        );
        assert_eq!(
            run.inputs(),
            [("git".to_string(), "name".to_string(), "me".to_string())]
        );
        assert_eq!(run.profile(), "demo");
        assert_eq!(run.meta("argv").as_deref(), Some("-p demo"));
        assert_eq!(run.private().as_deref(), Some("/media/usb/private"));
        assert_eq!(fs::read_link(store.latest_link()).unwrap(), run.dir());
        assert_eq!(run.step_log(3).unwrap().file_name().unwrap(), "03-git.log");
        assert!(run.step_log(4).is_err());

        assert_eq!(run.status("system"), Status::Pending);
        run.record("system", Status::Started, None).unwrap();
        run.record("system", Status::Done, None).unwrap();
        run.record("shell", Status::Started, None).unwrap();
        run.record("shell", Status::Failed, Some(3)).unwrap();
        assert_eq!(run.status("system"), Status::Done);
        assert_eq!(run.status("shell"), Status::Failed);
        assert_eq!(run.code("shell"), Some(3));
        assert!(run.is_resumable());
        assert!(
            run.describe()
                .ends_with("profile demo: 1/3 steps done, stopped at shell (failed)"),
            "{}",
            run.describe()
        );
        assert_eq!(store.resumable().unwrap().unwrap().dir(), run.dir());

        run.record("shell", Status::Done, None).unwrap();
        run.record("git", Status::Skipped, None).unwrap();
        assert!(run.is_complete());
        assert!(!run.is_resumable());
        assert!(store.resumable().unwrap().is_none());
        assert_eq!(store.latest().unwrap().unwrap().dir(), run.dir());
    }

    #[test]
    fn dry_runs_and_abandoned_runs_are_not_resumed() {
        let state = tempfile::tempdir().unwrap();
        let store = RunStore::new(state.path());
        let dry = store.create(&new_run("none", true)).unwrap();
        assert!(dry.is_dry_run() && !dry.is_resumable());
        assert!(
            !store.latest_link().exists(),
            "a dry run is not the latest run"
        );
        assert!(store.latest().unwrap().is_none());

        let run = store.create(&new_run("none", false)).unwrap();
        assert!(run.is_resumable());
        run.abandon().unwrap();
        assert!(!run.is_resumable());
    }

    #[test]
    fn prune_keeps_the_newest_and_the_resumable_runs() {
        let state = tempfile::tempdir().unwrap();
        let store = RunStore::new(state.path());
        let runs = store.runs_dir();
        for name in [
            "2026-01-01_000000",
            "2026-01-02_000000",
            "2026-01-02_000000.2",
            "2026-01-03_000000",
        ] {
            fs::create_dir_all(runs.join(name).join("steps")).unwrap();
            fs::write(runs.join(name).join("plan"), "unit a\n").unwrap();
            fs::write(
                runs.join(name).join("meta"),
                "profile=none\nstarted=0\ndry_run=0\n",
            )
            .unwrap();
            fs::write(runs.join(name).join("status"), "1 unit a done\n").unwrap();
        }
        // The oldest one is unfinished: resumable, kept
        fs::write(runs.join("2026-01-01_000000/status"), "").unwrap();
        let names = |store: &RunStore| -> Vec<String> {
            store
                .all()
                .unwrap()
                .iter()
                .map(|r| r.dir().file_name().unwrap().to_string_lossy().into_owned())
                .collect()
        };
        assert_eq!(
            names(&store),
            [
                "2026-01-03_000000",
                "2026-01-02_000000.2",
                "2026-01-02_000000",
                "2026-01-01_000000"
            ]
        );
        store.prune(1).unwrap();
        let mut left = names(&store);
        left.sort();
        assert_eq!(left, ["2026-01-01_000000", "2026-01-03_000000"]);
    }

    #[test]
    fn status_lines_with_a_trailing_space_or_a_stray_word_are_read() {
        let state = tempfile::tempdir().unwrap();
        let dir = state.path().join("runs/2026-01-01_000000");
        fs::create_dir_all(dir.join("steps")).unwrap();
        fs::write(dir.join("plan"), "unit a\nunit c\n\nbogus\n").unwrap();
        fs::write(dir.join("meta"), "profile=none\nstarted=0\ndry_run=0\n").unwrap();
        fs::write(
            dir.join("status"),
            "1 unit a started \n2 unit a done \n3 unit c mystery\n4 unit c failed 7\n",
        )
        .unwrap();
        let run = Run::open(&dir).unwrap();
        assert_eq!(run.steps(), ["a", "c"]);
        assert_eq!(run.status("a"), Status::Done);
        assert_eq!(run.status("c"), Status::Failed);
        assert_eq!(run.code("c"), Some(7));
        assert!(matches!(
            Run::open(state.path()),
            Err(JournalError::NoPlan { .. })
        ));
    }
}
