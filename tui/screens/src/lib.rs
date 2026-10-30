//! The selection screens (ratatui): a profile to start from, the units to
//! install with their variants, the answers to the questions, and the plan.
//! [`select`] runs them and returns what the user decided; nothing is
//! written to disk here.

mod app;
mod rows;
mod theme;
mod ui;

use std::time::Duration;

use crossterm::event::{self, Event, KeyEventKind};
use host::Machine;
use model::{Profiles, Registry, Selection};
use thiserror::Error;

pub use theme::{Glyphs, Palette};

/// What the screens show and start from.
pub struct SelectContext<'a> {
    pub registry: &'a Registry,
    pub profiles: &'a Profiles,
    pub machine: &'a Machine,
    /// An unfinished run, described, offered for resuming.
    pub resumable: Option<&'a str>,
    /// The private repository in use, shown on the first screen.
    pub private: Option<&'a str>,
    /// Plain symbols and borders (the Linux console).
    pub ascii: bool,
    /// Nothing will change: the run is a dry run.
    pub dry_run: bool,
    /// Only the files of the units will be deployed, then their hooks run.
    pub files_only: bool,
    /// Units selected from the start, the screens opening on their
    /// variants (`--config`).
    pub config: &'a [String],
}

/// What the user decided.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Quit,
    /// Run the selection, started from this profile ("none" for none).
    Run {
        profile: String,
        selection: Selection,
    },
    /// Resume the unfinished run.
    Resume,
    /// Save the selection as a profile of this name.
    Save {
        name: String,
        profile: String,
        selection: Selection,
    },
    /// Add this private repository (an URL or a folder), then come back.
    Private(String),
}

#[derive(Debug, Error)]
pub enum ScreenError {
    #[error("the terminal: {0}")]
    Terminal(#[from] std::io::Error),
}

/// Shows the screens until the user quits, runs, resumes, saves or adds a
/// private repository.
pub fn select(context: &SelectContext) -> Result<Outcome, ScreenError> {
    let mut app = app::App::new(context);
    let mut terminal = ratatui::init();
    let result = (|| -> Result<Outcome, ScreenError> {
        loop {
            terminal.draw(|frame| ui::draw(frame, &mut app))?;
            if let Some(outcome) = app.outcome.take() {
                return Ok(outcome);
            }
            if event::poll(Duration::from_millis(250))? {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Press {
                        app.handle_key(key);
                    }
                }
            }
        }
    })();
    ratatui::restore();
    result
}
