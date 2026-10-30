//! The console: the lines the setup prints, in color when the terminal
//! shows them and copied to the setup.log of the run; the status line a
//! step rewrites; the questions, asked on the terminal (/dev/tty) so that
//! they still work when the output is piped. The run itself is shown by
//! [`RunView`], the observer of the runner.

mod run;

use std::fs::{File, OpenOptions};
use std::io::{self, BufRead, BufReader, Write};
use std::path::Path;

use anyhow::{Context, Result, anyhow};
use chrono::Local;
use crossterm::style::{Attribute, Color as CColor, ResetColor, SetAttribute, SetForegroundColor};
use crossterm::terminal;
use nix::sys::termios::{LocalFlags, SetArg, tcgetattr, tcsetattr};
use screens::{Glyphs, Palette};

use crate::config::{Config, open_tty};

pub use run::RunView;

/// How a piece of a line looks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tone {
    Plain,
    Bold,
    Dim,
    Ok,
    Fail,
    Warn,
    Run,
    Accent,
}

/// A line made of pieces, each with its tone.
#[derive(Debug, Default, Clone)]
pub struct Line(Vec<(Tone, String)>);

impl Line {
    pub fn new() -> Line {
        Line::default()
    }

    pub fn push(mut self, tone: Tone, text: impl Into<String>) -> Line {
        self.0.push((tone, text.into()));
        self
    }

    /// The line without its tones, for the log.
    pub fn plain(&self) -> String {
        self.0.iter().map(|(_, text)| text.as_str()).collect()
    }
}

pub struct Console {
    pub palette: Palette,
    pub glyphs: Glyphs,
    color: bool,
    stdout_terminal: bool,
    terminal: bool,
    assume_yes: bool,
    log: Option<File>,
    status_shown: bool,
    cursor_hidden: bool,
}

impl Console {
    pub fn new(config: &Config) -> Console {
        Console {
            palette: Palette::new(config.ascii),
            glyphs: Glyphs::new(config.ascii),
            color: config.color,
            stdout_terminal: config.stdout_terminal,
            terminal: config.terminal,
            assume_yes: config.assume_yes,
            log: None,
            status_shown: false,
            cursor_hidden: false,
        }
    }

    /// A terminal is there for the questions and the attended units.
    pub fn terminal(&self) -> bool {
        self.terminal
    }

    /// Questions can be asked: a terminal, and no --yes.
    pub fn can_prompt(&self) -> bool {
        self.terminal && !self.assume_yes
    }

    /// Copies the lines said from now on to this file.
    pub fn open_log(&mut self, path: &Path) -> Result<()> {
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .with_context(|| format!("opening {}", path.display()))?;
        self.log = Some(file);
        Ok(())
    }

    pub fn close_log(&mut self) {
        self.log = None;
    }

    fn log_line(&mut self, plain: &str) {
        if let Some(log) = &mut self.log {
            let _ = writeln!(log, "{} {plain}", Local::now().format("%H:%M:%S"));
        }
    }

    fn style(&self, tone: Tone) -> String {
        if !self.color {
            return String::new();
        }
        let p = &self.palette;
        let fg = |color| SetForegroundColor(CColor::from(color)).to_string();
        match tone {
            Tone::Plain => String::new(),
            Tone::Bold => SetAttribute(Attribute::Bold).to_string(),
            Tone::Dim => format!("{}{}", SetAttribute(Attribute::Dim), fg(p.dim)),
            Tone::Ok => fg(p.green),
            Tone::Fail => fg(p.red),
            Tone::Warn => fg(p.yellow),
            Tone::Run => fg(p.cyan),
            Tone::Accent => format!("{}{}", SetAttribute(Attribute::Bold), fg(p.accent)),
        }
    }

    fn render(&self, line: &Line) -> String {
        let mut out = String::new();
        for (tone, text) in &line.0 {
            if *tone == Tone::Plain || !self.color {
                out.push_str(text);
            } else {
                out.push_str(&format!(
                    "{}{text}{}{}",
                    self.style(*tone),
                    SetAttribute(Attribute::Reset),
                    ResetColor
                ));
            }
        }
        out
    }

    /// Prints a line, and logs it with the time.
    pub fn say(&mut self, line: Line) {
        self.clear_status();
        let rendered = self.render(&line);
        let mut stdout = io::stdout().lock();
        let _ = writeln!(stdout, "{rendered}");
        let _ = stdout.flush();
        drop(stdout);
        self.log_line(&line.plain());
    }

    /// Prints a line as it is, without logging it: what a step printed
    /// itself (its log has it).
    pub fn passthrough(&mut self, text: &str) {
        self.clear_status();
        let mut stdout = io::stdout().lock();
        let _ = writeln!(stdout, "{text}");
        let _ = stdout.flush();
    }

    pub fn text(&mut self, text: &str) {
        self.say(Line::new().push(Tone::Plain, text));
    }

    pub fn blank(&mut self) {
        self.say(Line::new());
    }

    pub fn title(&mut self, text: &str) {
        self.say(Line::new().push(Tone::Accent, text));
    }

    fn message(&mut self, tone: Tone, tag: &str, text: &str) {
        self.say(
            Line::new()
                .push(tone, format!("[{tag}]"))
                .push(Tone::Plain, format!(" {text}")),
        );
    }

    pub fn info(&mut self, text: &str) {
        self.message(Tone::Accent, "i", text);
    }

    pub fn success(&mut self, text: &str) {
        let ok = self.glyphs.ok;
        self.message(Tone::Ok, ok, text);
    }

    pub fn warn(&mut self, text: &str) {
        self.message(Tone::Warn, "!", text);
    }

    pub fn error(&mut self, text: &str) {
        let fail = self.glyphs.fail;
        self.message(Tone::Fail, fail, text);
    }

    /// The columns of the terminal.
    pub fn width(&self) -> usize {
        terminal::size().map(|(w, _)| w as usize).unwrap_or(80)
    }

    /// Cuts a text to the terminal width, keeping room for `reserve`
    /// columns, with an ellipsis.
    pub fn fit(&self, text: &str, reserve: usize) -> String {
        let room = self.width().saturating_sub(reserve);
        let count = text.chars().count();
        if count <= room {
            return text.to_string();
        }
        let ellipsis = self.glyphs.ellipsis;
        let keep = room.saturating_sub(ellipsis.chars().count());
        format!("{}{ellipsis}", text.chars().take(keep).collect::<String>())
    }

    /// Rewrites the current line with a symbol and a text: the spinner.
    /// Only when stdout is a terminal.
    pub fn status(&mut self, symbol: &str, tone: Tone, text: &str) {
        if !self.stdout_terminal {
            return;
        }
        let line = Line::new()
            .push(tone, symbol)
            .push(Tone::Plain, format!(" {}", self.fit(text, 5)));
        let rendered = self.render(&line);
        let mut stdout = io::stdout().lock();
        let _ = write!(stdout, "\r  {rendered}\x1b[K");
        let _ = stdout.flush();
        self.status_shown = true;
    }

    pub fn clear_status(&mut self) {
        if self.status_shown {
            let mut stdout = io::stdout().lock();
            let _ = write!(stdout, "\r\x1b[K");
            let _ = stdout.flush();
            self.status_shown = false;
        }
    }

    pub fn hide_cursor(&mut self) {
        if self.stdout_terminal && !self.cursor_hidden {
            let _ = write!(io::stdout(), "\x1b[?25l");
            let _ = io::stdout().flush();
            self.cursor_hidden = true;
        }
    }

    pub fn show_cursor(&mut self) {
        if self.cursor_hidden {
            let _ = write!(io::stdout(), "\x1b[?25h");
            let _ = io::stdout().flush();
            self.cursor_hidden = false;
        }
    }

    /// Writes a prompt on the terminal and reads the line typed, hidden for
    /// a secret.
    fn read_line(&mut self, prompt: &str, hidden: bool) -> Result<String> {
        self.clear_status();
        let rendered = self.render(
            &Line::new()
                .push(Tone::Run, "[?]")
                .push(Tone::Plain, format!(" {prompt} ")),
        );
        let mut tty = open_tty()?;
        write!(tty, "{rendered}")?;
        tty.flush()?;
        let saved = if hidden {
            let saved = tcgetattr(&tty).context("reading the terminal settings")?;
            let mut quiet = saved.clone();
            quiet.local_flags.remove(LocalFlags::ECHO);
            tcsetattr(&tty, SetArg::TCSANOW, &quiet).context("hiding the typed text")?;
            Some(saved)
        } else {
            None
        };
        let mut answer = String::new();
        let read = BufReader::new(&tty).read_line(&mut answer);
        if let Some(saved) = saved {
            let _ = tcsetattr(&tty, SetArg::TCSANOW, &saved);
            let _ = writeln!(tty);
        }
        read.context("reading the answer")?;
        Ok(answer.trim_end_matches(['\n', '\r']).to_string())
    }

    /// Asks a yes/no question, yes being the answer to Enter unless
    /// `default_yes` is false. Without a terminal, or with --yes, says the
    /// default and answers it.
    pub fn confirm(&mut self, question: &str, default_yes: bool) -> Result<bool> {
        let choices = if default_yes { "[Y/n]" } else { "[y/N]" };
        if !self.can_prompt() {
            let answer = if default_yes { "yes" } else { "no" };
            self.info(&format!(
                "{question} {choices} {answer} (assumed: no terminal, or --yes)"
            ));
            return Ok(default_yes);
        }
        let answer = self.read_line(&format!("{question} {choices}"), false)?;
        self.log_line(&format!("[?] {question} {choices} {answer}"));
        Ok(match answer.trim().to_lowercase().as_str() {
            "" => default_yes,
            a if a.starts_with('y') => true,
            a if a.starts_with('n') => false,
            _ => default_yes,
        })
    }

    /// Asks for a text; Enter gives the default when there is one. Without
    /// a terminal, or with --yes, the default is the answer.
    pub fn ask(&mut self, prompt: &str, default: Option<&str>) -> Result<String> {
        let shown = default
            .map(|d| format!("{prompt} [{d}]"))
            .unwrap_or_else(|| prompt.to_string());
        if !self.can_prompt() {
            return default.map(str::to_string).ok_or_else(|| {
                anyhow!("no terminal to ask: {prompt} (pass the answer in a profile, or run from a terminal)")
            });
        }
        let answer = self.read_line(&shown, false)?;
        self.log_line(&format!("[?] {shown} {answer}"));
        Ok(if answer.trim().is_empty() {
            default.unwrap_or_default().to_string()
        } else {
            answer
        })
    }

    /// Asks for a secret: typed hidden, never logged.
    pub fn ask_secret(&mut self, prompt: &str) -> Result<String> {
        if !self.can_prompt() {
            return Err(anyhow!("no terminal to ask: {prompt}"));
        }
        let answer = self.read_line(prompt, true)?;
        self.log_line(&format!("[?] {prompt} (secret)"));
        Ok(answer)
    }

    /// Waits for Enter, when a terminal is there.
    pub fn pause(&mut self, text: &str) -> Result<()> {
        if self.can_prompt() {
            self.read_line(text, false)?;
        }
        Ok(())
    }
}

/// The cursor comes back whatever happens.
impl Drop for Console {
    fn drop(&mut self) {
        self.clear_status();
        self.show_cursor();
    }
}

/// A duration as 5s, 2m05s or 1h02m.
pub fn format_duration(seconds: u64) -> String {
    if seconds >= 3600 {
        format!("{}h{:02}m", seconds / 3600, seconds % 3600 / 60)
    } else if seconds >= 60 {
        format!("{}m{:02}s", seconds / 60, seconds % 60)
    } else {
        format!("{seconds}s")
    }
}

/// A count followed by a noun, plural when needed (1 step, 2 steps).
pub fn plural(count: usize, noun: &str) -> String {
    if count == 1 {
        format!("1 {noun}")
    } else {
        format!("{count} {noun}s")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn durations_and_plurals_read_like_the_setup() {
        assert_eq!(format_duration(5), "5s");
        assert_eq!(format_duration(125), "2m05s");
        assert_eq!(format_duration(3720), "1h02m");
        assert_eq!(plural(1, "step"), "1 step");
        assert_eq!(plural(3, "unit"), "3 units");
    }

    #[test]
    fn a_line_logs_without_its_tones() {
        let line = Line::new().push(Tone::Ok, "ok").push(Tone::Plain, " done");
        assert_eq!(line.plain(), "ok done");
    }
}
