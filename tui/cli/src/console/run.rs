//! The run on the console: the plan with the status of the steps already
//! run, a line per step as it runs (the spinner, or the step's own output
//! for an attended one), the report of a failure with how to resume, and
//! the summary.

use std::path::{Path, PathBuf};

use journal::{Run, Status};
use model::Registry;
use runner::{
    Failure, Observer, Progress, RunOutcome, RunStatus, SkipReason, StepOutcome, StepView,
};

use crate::config::tilde;
use crate::console::{Console, Line, Tone, format_duration, plural};

/// The columns of the step lines.
struct Columns {
    total: usize,
    index_width: usize,
    id_width: usize,
}

impl Columns {
    fn new(steps: &[String]) -> Columns {
        Columns {
            total: steps.len(),
            index_width: steps.len().to_string().len(),
            id_width: steps.iter().map(|s| s.chars().count()).max().unwrap_or(0),
        }
    }

    /// The start of a step line: its number over the total, then its id.
    fn position(&self, index: usize, id: &str) -> String {
        format!(
            "{index:>iw$}/{}  {id:<lw$}",
            self.total,
            iw = self.index_width,
            lw = self.id_width
        )
    }
}

/// Shows a run as it happens.
pub struct RunView<'c> {
    console: &'c mut Console,
    columns: Columns,
    frame: usize,
    /// The command resuming the run, for the messages.
    resume_command: String,
    dry_run: bool,
    files_only: bool,
    home: PathBuf,
}

impl<'c> RunView<'c> {
    pub fn new(
        console: &'c mut Console,
        run: &Run,
        resume_command: String,
        dry_run: bool,
        files_only: bool,
        home: &Path,
    ) -> RunView<'c> {
        RunView {
            console,
            columns: Columns::new(run.steps()),
            frame: 0,
            resume_command,
            dry_run,
            files_only,
            home: home.to_path_buf(),
        }
    }

    /// A step line: its mark, its position (bold when it stands out) and
    /// the rest.
    fn step_line(mark: &str, tone: Tone, position: &str, bold: bool, rest: Line) -> Line {
        let mut line = Line::new().push(Tone::Plain, "  ").push(tone, mark).push(
            if bold { Tone::Bold } else { Tone::Plain },
            format!(" {position}"),
        );
        for (tone, text) in rest.0 {
            line = line.push(tone, text);
        }
        line
    }

    /// The title, where the logs are, and the steps with the status of the
    /// ones already run.
    pub fn print_plan(&mut self, run: &Run, registry: &Registry) {
        let dot = self.console.glyphs.dot;
        let files = if self.files_only {
            format!(" {dot} files only")
        } else {
            String::new()
        };
        let dry = if self.dry_run {
            format!(" {dot} dry run")
        } else {
            String::new()
        };
        self.console.blank();
        self.console.title(&format!(
            "Arch setup {dot} {} {dot} profile {}{files}{dry}",
            plural(self.columns.total, "step"),
            run.profile()
        ));
        let logs = tilde(run.dir(), &self.home);
        self.console
            .say(Line::new().push(Tone::Dim, format!("Logs: {logs}")));
        self.console.blank();

        let glyphs = self.console.glyphs;
        for (i, id) in run.steps().iter().enumerate() {
            let unit = registry.unit(id);
            let attended = unit.is_some_and(|u| u.attended());
            let (mark, tone, note) = match run.status(id) {
                Status::Done => (glyphs.ok, Tone::Ok, "done earlier"),
                Status::Skipped => (glyphs.skip, Tone::Warn, "skipped earlier"),
                Status::Started | Status::Failed | Status::Interrupted => {
                    (glyphs.fail, Tone::Fail, "to run again")
                }
                Status::Pending if attended => (" ", Tone::Plain, "needs the terminal"),
                Status::Pending => (" ", Tone::Plain, ""),
            };
            let name = unit.map(|u| u.name()).unwrap_or_default();
            let mut rest = Line::new().push(Tone::Plain, format!("  {name}"));
            if !note.is_empty() {
                rest = rest.push(Tone::Dim, format!("  ({note})"));
            }
            let position = self.columns.position(i + 1, id);
            self.console
                .say(RunView::step_line(mark, tone, &position, false, rest));
        }
        self.console.blank();
    }

    /// How the run ended: how many steps are done, how long it took and
    /// where the logs are.
    pub fn summary(&mut self, run: &Run, outcome: &RunOutcome) {
        let total = run.steps().len();
        let duration = format_duration(outcome.duration.as_secs());
        let summary = if outcome.skipped > 0 {
            format!(
                "{}/{total} steps done, {} skipped in {duration}",
                outcome.done, outcome.skipped
            )
        } else {
            format!("{}/{total} steps done in {duration}", outcome.done)
        };
        self.console.blank();
        match outcome.status {
            RunStatus::Failed => self.console.error(&format!("Setup stopped: {summary}.")),
            RunStatus::Interrupted => self.console.warn(&format!("Setup interrupted: {summary}.")),
            RunStatus::Completed if self.files_only => {
                self.console.success(&format!("Files deployed: {summary}."));
            }
            RunStatus::Completed if self.dry_run => self.console.success(&format!(
                "Dry run finished: {summary}. Nothing was changed."
            )),
            RunStatus::Completed => {
                self.console
                    .success(&format!("Setup completed: {summary}."));
                if outcome.done > 0 {
                    self.console
                        .text("  Reboot to apply everything (drivers, services, login screen).");
                }
            }
        }
        let logs = tilde(run.dir(), &self.home);
        self.console
            .say(Line::new().push(Tone::Dim, format!("  Logs: {logs}")));
    }

    /// The report of a failed step: the last lines of its log, the failed
    /// command, the probable cause and how to resume.
    fn failure(&mut self, position: &str, name: &str, failure: &Failure) {
        let glyphs = self.console.glyphs;
        let rest = Line::new()
            .push(Tone::Plain, format!("  {name}  "))
            .push(Tone::Fail, "failed")
            .push(
                Tone::Dim,
                format!(
                    " ({}, code {} after {})",
                    failure.phase.describe(),
                    failure.code,
                    format_duration(failure.duration.as_secs())
                ),
            );
        self.console.say(RunView::step_line(
            glyphs.fail,
            Tone::Fail,
            position,
            true,
            rest,
        ));
        self.console.blank();
        if !failure.log_tail.is_empty() {
            self.console.text("  Last lines of the log:");
            for line in &failure.log_tail {
                let fitted = self.console.fit(line, 7);
                self.console.say(
                    Line::new()
                        .push(Tone::Dim, format!("    {} ", glyphs.bar))
                        .push(Tone::Plain, fitted),
                );
            }
            self.console.blank();
        }
        if let Some(command) = &failure.command {
            self.console.say(
                Line::new()
                    .push(Tone::Bold, "  Failed command: ")
                    .push(Tone::Plain, command.clone()),
            );
        }
        self.console.say(
            Line::new()
                .push(Tone::Bold, "  Probable cause: ")
                .push(Tone::Plain, failure.cause),
        );
        let log = tilde(&failure.log, &self.home);
        self.console.say(
            Line::new()
                .push(Tone::Bold, "  Full log: ")
                .push(Tone::Plain, log),
        );
        self.console.say(
            Line::new()
                .push(Tone::Bold, "  To resume: ")
                .push(Tone::Plain, self.resume_command.clone())
                .push(
                    Tone::Dim,
                    "  (runs this step again and the next ones, not the done ones)",
                ),
        );
    }
}

impl Observer for RunView<'_> {
    fn step_started(&mut self, step: &StepView) {
        if step.attended && !self.dry_run {
            // The step has the terminal: its line stays, its output follows
            let position = self.columns.position(step.index, step.unit.id());
            let rest = Line::new().push(Tone::Plain, format!("  {}", step.unit.name()));
            let run = self.console.glyphs.run;
            self.console
                .say(RunView::step_line(run, Tone::Run, &position, true, rest));
        } else {
            self.console.hide_cursor();
        }
    }

    fn step_progress(&mut self, step: &StepView, progress: &Progress) {
        let glyphs = self.console.glyphs;
        let dot = glyphs.dot;
        let message = progress
            .message
            .as_ref()
            .map(|m| format!(" {dot} {m}"))
            .unwrap_or_default();
        let text = format!(
            "{}  {} {dot} {}{message} ({})",
            self.columns.position(step.index, step.unit.id()),
            step.unit.name(),
            progress.phase.describe(),
            format_duration(progress.elapsed.as_secs())
        );
        self.console
            .status(glyphs.spinner[self.frame], Tone::Run, &text);
        self.frame = (self.frame + 1) % glyphs.spinner.len();
    }

    fn step_output(&mut self, _step: &StepView, line: &str) {
        self.console.passthrough(line);
    }

    fn step_finished(&mut self, step: &StepView, outcome: &StepOutcome) {
        self.console.clear_status();
        self.console.show_cursor();
        let glyphs = self.console.glyphs;
        let position = self.columns.position(step.index, step.unit.id());
        let name = step.unit.name();
        match outcome {
            StepOutcome::Done { duration } => {
                let took = if self.dry_run {
                    "dry run".to_string()
                } else {
                    format_duration(duration.as_secs())
                };
                let rest = Line::new()
                    .push(Tone::Plain, format!("  {name}  "))
                    .push(Tone::Dim, format!("({took})"));
                self.console.say(RunView::step_line(
                    glyphs.ok,
                    Tone::Ok,
                    &position,
                    false,
                    rest,
                ));
            }
            StepOutcome::DoneEarlier => {
                let rest = Line::new().push(Tone::Dim, "  done earlier");
                self.console.say(RunView::step_line(
                    glyphs.ok,
                    Tone::Ok,
                    &position,
                    false,
                    rest,
                ));
            }
            StepOutcome::Skipped(SkipReason::Attended) => {
                let rest = Line::new().push(
                    Tone::Dim,
                    "  skipped: it needs the terminal (run it again from one, without --yes)",
                );
                self.console.say(RunView::step_line(
                    glyphs.skip,
                    Tone::Warn,
                    &position,
                    false,
                    rest,
                ));
            }
            StepOutcome::Failed(failure) => self.failure(&position, name, failure),
            StepOutcome::Interrupted => {
                let rest = Line::new()
                    .push(Tone::Plain, format!("  {name}  "))
                    .push(Tone::Warn, "interrupted");
                self.console.say(RunView::step_line(
                    glyphs.fail,
                    Tone::Warn,
                    &position,
                    true,
                    rest,
                ));
                self.console.blank();
                self.console.warn(&format!(
                    "Interrupted during step {}/{} {}. Resume with: {}",
                    step.index,
                    step.total,
                    step.unit.id(),
                    self.resume_command
                ));
            }
        }
    }

    fn waiting_for(&mut self, tool: &str) {
        let dot = self.console.glyphs.dot;
        self.console.status(
            dot,
            Tone::Warn,
            &format!("waiting for {tool} to finish its package (Ctrl-C again detaches it)"),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn positions_line_up() {
        let steps: Vec<String> = ["base", "desktop-tools", "git"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let columns = Columns::new(&steps);
        assert_eq!(columns.position(1, "base"), "1/3  base         ");
        assert_eq!(columns.position(3, "git"), "3/3  git          ");
        let many: Vec<String> = (0..12).map(|i| format!("u{i}")).collect();
        assert_eq!(Columns::new(&many).position(7, "u6"), " 7/12  u6 ");
    }
}
