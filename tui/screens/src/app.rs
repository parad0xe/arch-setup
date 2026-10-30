//! The state of the screens and what the keys do to it.

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use host::Machine;
use model::{InputKind, InputValue, Plan, Profiles, Registry, Selection, plan};

use crate::rows::{self, Row};
use crate::theme::Theme;
use crate::{Outcome, SelectContext};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Screen {
    Profile,
    Units,
    Variants,
    Inputs,
    Summary,
}

impl Screen {
    pub(crate) const ALL: [Screen; 5] = [
        Screen::Profile,
        Screen::Units,
        Screen::Variants,
        Screen::Inputs,
        Screen::Summary,
    ];

    pub(crate) fn index(self) -> usize {
        Screen::ALL.iter().position(|s| *s == self).unwrap_or(0)
    }

    /// The lists the filter applies to.
    pub(crate) fn filterable(self) -> bool {
        matches!(self, Screen::Units | Screen::Variants | Screen::Inputs)
    }

    pub(crate) fn title(self) -> &'static str {
        match self {
            Screen::Profile => "Profile",
            Screen::Units => "Units",
            Screen::Variants => "Variants",
            Screen::Inputs => "Answers",
            Screen::Summary => "Summary",
        }
    }
}

/// What the text typed in the status bar is for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Edit {
    Filter,
    ProfileName,
    Private,
    Input {
        unit: String,
        input: String,
        secret: bool,
    },
}

pub(crate) struct App<'a> {
    pub(crate) registry: &'a Registry,
    pub(crate) profiles: &'a Profiles,
    pub(crate) machine: &'a Machine,
    pub(crate) resumable: Option<String>,
    pub(crate) private: Option<String>,
    pub(crate) dry_run: bool,
    pub(crate) files_only: bool,
    pub(crate) theme: Theme,
    pub(crate) screen: Screen,
    pub(crate) selection: Selection,
    /// The profile started from, "none" for none.
    pub(crate) profile: String,
    cursor: [usize; 5],
    /// The first row shown on each screen.
    offset: [usize; 5],
    pub(crate) filter: String,
    pub(crate) edit: Option<Edit>,
    pub(crate) edit_text: String,
    pub(crate) help: bool,
    pub(crate) message: Option<String>,
    pub(crate) outcome: Option<Outcome>,
}

impl<'a> App<'a> {
    pub(crate) fn new(context: &SelectContext<'a>) -> App<'a> {
        let mut app = App {
            registry: context.registry,
            profiles: context.profiles,
            machine: context.machine,
            resumable: context.resumable.map(str::to_string),
            private: context.private.map(str::to_string),
            dry_run: context.dry_run,
            files_only: context.files_only,
            theme: Theme::new(context.ascii),
            screen: Screen::Profile,
            selection: Selection::new(),
            profile: "none".to_string(),
            cursor: [0; 5],
            offset: [0; 5],
            filter: String::new(),
            edit: None,
            edit_text: String::new(),
            help: false,
            message: None,
            outcome: None,
        };
        // --config: the units given are selected and the screens open on
        // what comes after the units
        for unit in context.config {
            app.selection.select(unit);
        }
        if !context.config.is_empty() {
            app.screen = app.after_units();
        }
        app
    }

    /// The plan of the selection; in files-only mode, its units with files.
    pub(crate) fn plan(&self) -> Plan {
        let plan = plan::build(self.registry, &self.selection);
        if self.files_only {
            plan.keeping(|s| {
                self.registry
                    .unit(s.unit())
                    .is_some_and(|u| !u.files().is_empty())
            })
        } else {
            plan
        }
    }

    /// The rows of the current screen, filtered on the units and inputs
    /// screens (a section stays when one of its lines matches).
    pub(crate) fn rows(&self) -> Vec<Row> {
        let rows = match self.screen {
            Screen::Profile => self.profile_rows(),
            Screen::Units => rows::units(self.registry, &self.selection, self.files_only),
            Screen::Variants => rows::variants(self.registry, &self.selection, &self.plan()),
            Screen::Inputs => rows::inputs(self.registry, &self.selection, &self.plan()),
            Screen::Summary => rows::summary(&self.plan()),
        };
        if self.filter.is_empty() || !self.screen.filterable() {
            return rows;
        }
        let needle = self.filter.to_lowercase();
        let mut kept: Vec<Row> = Vec::new();
        let mut section: Option<Row> = None;
        for row in rows {
            if let Row::Section { .. } = &row {
                section = Some(row);
            } else if row
                .search_text(self.registry)
                .to_lowercase()
                .contains(&needle)
            {
                if let Some(section) = section.take() {
                    kept.push(section);
                }
                kept.push(row);
            }
        }
        kept
    }

    fn profile_rows(&self) -> Vec<Row> {
        let mut rows = Vec::new();
        if let Some(description) = &self.resumable {
            rows.push(Row::Resume {
                description: description.clone(),
            });
        }
        rows.push(Row::Private {
            source: self.private.clone(),
        });
        rows.push(Row::Profile {
            name: "none".to_string(),
        });
        rows.extend(self.profiles.names().map(|name| Row::Profile {
            name: name.to_string(),
        }));
        rows
    }

    pub(crate) fn cursor(&self) -> usize {
        self.cursor[self.screen.index()]
    }

    /// The first row to show in a list of `visible` lines: the cursor keeps
    /// a few lines between itself and the edges while it moves.
    pub(crate) fn scroll(&mut self, rows: usize, visible: usize) -> usize {
        let i = self.screen.index();
        let visible = visible.max(1);
        let margin = (visible.saturating_sub(1) / 2).min(3);
        let cursor = self.cursor();
        let mut offset = self.offset[i];
        if cursor < offset + margin {
            offset = cursor.saturating_sub(margin);
        }
        if cursor + margin >= offset + visible {
            offset = (cursor + margin + 1).saturating_sub(visible);
        }
        offset = offset.min(rows.saturating_sub(visible));
        self.offset[i] = offset;
        offset
    }

    pub(crate) fn current_row(&self) -> Option<Row> {
        self.rows().get(self.cursor()).cloned()
    }

    fn move_cursor(&mut self, delta: isize) {
        let rows = self.rows();
        if rows.is_empty() {
            return;
        }
        let i = self.screen.index();
        let mut next = (self.cursor[i] as isize + delta).clamp(0, rows.len() as isize - 1) as usize;
        // Separators are skipped in the direction of the move
        while !rows[next].is_item() {
            let step = if delta < 0 { -1 } else { 1 };
            let candidate = next as isize + step;
            if candidate < 0 || candidate >= rows.len() as isize {
                break;
            }
            next = candidate as usize;
        }
        self.cursor[i] = next;
    }

    fn clamp_cursor(&mut self) {
        let count = self.rows().len();
        let i = self.screen.index();
        if count == 0 {
            self.cursor[i] = 0;
        } else if self.cursor[i] >= count {
            self.cursor[i] = count - 1;
        }
    }

    fn goto(&mut self, screen: Screen) {
        self.screen = screen;
        self.filter.clear();
        self.message = None;
        self.clamp_cursor();
    }

    /// The text at the bottom of the list.
    pub(crate) fn status(&self) -> String {
        let dot = self.theme.glyphs.dot;
        match self.screen {
            Screen::Profile => "pick a profile to start from".to_string(),
            Screen::Units => {
                let added = rows::implied(self.registry, &self.selection)
                    .keys()
                    .filter(|id| self.deployable(id))
                    .count();
                let more = if added > 0 {
                    format!(", +{added} required")
                } else {
                    String::new()
                };
                format!(
                    "profile {} {dot} {} selected{more}",
                    self.profile,
                    self.selection
                        .units()
                        .filter(|id| self.deployable(id))
                        .count()
                )
            }
            Screen::Variants => {
                let (picked, total) = self.variant_counts();
                format!("{total} variants {dot} {picked} picked, the others by default")
            }
            Screen::Inputs => {
                let plan = self.plan();
                let missing = rows::missing_required(self.registry, &self.selection, &plan).len();
                if missing > 0 {
                    format!("{missing} required answer(s) missing")
                } else {
                    "every answer set".to_string()
                }
            }
            Screen::Summary => {
                let plan = self.plan();
                let files = if self.files_only {
                    format!(" {dot} files only")
                } else {
                    String::new()
                };
                let dry = if self.dry_run {
                    format!(" {dot} nothing will change (dry run)")
                } else {
                    String::new()
                };
                format!(
                    "{} steps {dot} in run order{files}{dry}",
                    plan.steps().len()
                )
            }
        }
    }

    /// The key hints of the status bar: (key, what it does).
    pub(crate) fn hints(&self) -> Vec<(&'static str, &'static str)> {
        let arrows = self.theme.glyphs.arrows;
        match self.screen {
            Screen::Profile => vec![
                ("Enter", "start from this profile"),
                ("q", "quit"),
                ("?", "help"),
            ],
            Screen::Units => vec![
                ("Space", "select"),
                ("Enter", "next"),
                ("/", "filter"),
                ("Esc", "back"),
                ("?", "help"),
            ],
            Screen::Variants => vec![
                (arrows, "option"),
                ("Enter", "next"),
                ("/", "filter"),
                ("Esc", "back"),
                ("?", "help"),
            ],
            Screen::Inputs => vec![
                ("Enter", "answer"),
                ("Space", "toggle"),
                (arrows, "option"),
                ("Del", "clear"),
                ("Tab", "summary"),
                ("Esc", "back"),
                ("?", "help"),
            ],
            Screen::Summary => vec![
                (
                    "Enter",
                    if self.files_only {
                        "deploy files"
                    } else if self.dry_run {
                        "dry run"
                    } else {
                        "run"
                    },
                ),
                ("s", "save as a profile"),
                ("Esc", "back"),
                ("?", "help"),
            ],
        }
    }

    pub(crate) fn handle_key(&mut self, key: KeyEvent) {
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            self.outcome = Some(Outcome::Quit);
            return;
        }
        if self.help {
            self.help = false;
            return;
        }
        if self.edit.is_some() {
            self.handle_edit_key(key);
            return;
        }
        self.message = None;
        match key.code {
            KeyCode::Char('?') => self.help = true,
            KeyCode::Char('q') => self.outcome = Some(Outcome::Quit),
            KeyCode::Up | KeyCode::Char('k') => self.move_cursor(-1),
            KeyCode::Down | KeyCode::Char('j') => self.move_cursor(1),
            KeyCode::PageUp => self.move_cursor(-10),
            KeyCode::PageDown => self.move_cursor(10),
            KeyCode::Home | KeyCode::Char('g') => self.move_cursor(isize::MIN / 2),
            KeyCode::End | KeyCode::Char('G') => self.move_cursor(isize::MAX / 2),
            KeyCode::Char('/') if self.screen.filterable() => {
                self.edit = Some(Edit::Filter);
                self.edit_text = self.filter.clone();
            }
            KeyCode::Char(' ') => self.toggle(),
            KeyCode::Tab if self.screen == Screen::Inputs => self.goto(Screen::Summary),
            KeyCode::Left => self.cycle(-1),
            KeyCode::Right => self.cycle(1),
            KeyCode::Char('s') if self.screen == Screen::Summary => {
                self.edit = Some(Edit::ProfileName);
                self.edit_text = if self.profile == "none" {
                    "mine".to_string()
                } else {
                    self.profile.clone()
                };
            }
            KeyCode::Delete if self.screen == Screen::Inputs => self.clear_answer(),
            KeyCode::Enter => self.enter(),
            KeyCode::Esc => self.back(),
            _ => {}
        }
    }

    fn handle_edit_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Esc => {
                if self.edit == Some(Edit::Filter) {
                    self.filter.clear();
                    self.clamp_cursor();
                }
                self.edit = None;
                self.edit_text.clear();
            }
            KeyCode::Enter => {
                let text = std::mem::take(&mut self.edit_text);
                match self.edit.take() {
                    Some(Edit::Filter) => {
                        self.filter = text;
                        self.clamp_cursor();
                    }
                    Some(Edit::ProfileName) => self.save(&text),
                    Some(Edit::Private) => {
                        if !text.trim().is_empty() {
                            self.outcome = Some(Outcome::Private(text.trim().to_string()));
                        }
                    }
                    Some(Edit::Input { unit, input, .. }) => self.answer(&unit, &input, text),
                    None => {}
                }
            }
            KeyCode::Backspace => {
                self.edit_text.pop();
                if self.edit == Some(Edit::Filter) {
                    self.filter = self.edit_text.clone();
                    self.clamp_cursor();
                }
            }
            KeyCode::Char(' ') | KeyCode::Tab if self.edit == Some(Edit::Filter) => {
                // Space and Tab keep selecting while filtering
                self.toggle();
            }
            KeyCode::Char(c) => {
                self.edit_text.push(c);
                if self.edit == Some(Edit::Filter) {
                    self.filter = self.edit_text.clone();
                    self.clamp_cursor();
                }
            }
            _ => {}
        }
    }

    /// Space: a unit, a whole module, or a yes/no answer.
    fn toggle(&mut self) {
        let Some(row) = self.current_row() else {
            return;
        };
        match row {
            Row::Section { id, .. } if self.screen == Screen::Units => {
                let ids: Vec<String> = self
                    .registry
                    .units()
                    .filter(|u| u.module() == id && u.offered() && self.deployable(u.id()))
                    .map(|u| u.id().to_string())
                    .collect();
                if ids.iter().all(|id| self.selection.contains(id)) {
                    for id in ids {
                        self.selection.unselect(&id);
                    }
                } else {
                    for id in ids {
                        self.selection.select(&id);
                    }
                }
                self.move_cursor(1);
            }
            Row::Unit { id, .. } => {
                self.selection.toggle(&id);
                self.move_cursor(1);
            }
            Row::Variant { .. } => self.cycle(1),
            Row::Input { unit, input, .. } => {
                if self
                    .registry
                    .unit(&unit)
                    .and_then(|u| u.input(&input))
                    .is_some_and(|i| i.kind == InputKind::Bool)
                {
                    let current = match self.selection.input(&unit, &input) {
                        Some(InputValue::Flag(flag)) => *flag,
                        _ => {
                            self.registry
                                .unit(&unit)
                                .and_then(|u| u.input(&input))
                                .and_then(|i| i.default.clone())
                                .as_deref()
                                == Some("true")
                        }
                    };
                    self.selection
                        .set_input(&unit, &input, InputValue::Flag(!current));
                } else {
                    self.enter();
                }
            }
            _ => {}
        }
    }

    /// Left and right: the option of a variant or of a choice input.
    fn cycle(&mut self, step: isize) {
        let Some(row) = self.current_row() else {
            return;
        };
        match row {
            Row::Variant {
                unit,
                variant,
                option,
            } => {
                let Some(options) = self
                    .registry
                    .unit(&unit)
                    .and_then(|u| u.variant(&variant))
                    .map(|v| v.options.clone())
                else {
                    return;
                };
                let next = next_of(&options, &option, step);
                self.selection.set_variant(&unit, &variant, &next);
            }
            Row::Input { unit, input, .. } => {
                let Some(decl) = self.registry.unit(&unit).and_then(|u| u.input(&input)) else {
                    return;
                };
                match decl.kind {
                    InputKind::Choice => {
                        let values: Vec<String> =
                            decl.options.iter().map(|o| o.value.clone()).collect();
                        let current = match self.selection.input(&unit, &input) {
                            Some(InputValue::Text(text)) => text.clone(),
                            _ => decl.default.clone().unwrap_or_default(),
                        };
                        let next = next_of(&values, &current, step);
                        self.selection
                            .set_input(&unit, &input, InputValue::Text(next));
                    }
                    InputKind::Bool => self.toggle(),
                    _ => {}
                }
            }
            _ => {}
        }
    }

    fn enter(&mut self) {
        match self.screen {
            Screen::Profile => match self.current_row() {
                Some(Row::Resume { .. }) => self.outcome = Some(Outcome::Resume),
                Some(Row::Private { source }) => {
                    self.edit = Some(Edit::Private);
                    self.edit_text = source.unwrap_or_default();
                }
                Some(Row::Profile { name }) => {
                    self.profile = name.clone();
                    let mut note = None;
                    let mut selection = if name == "none" {
                        Selection::new()
                    } else {
                        match self.profiles.resolve(&name, self.registry) {
                            Ok(resolved) => {
                                if !resolved.warnings.is_empty() {
                                    note = Some(resolved.warnings.join("; "));
                                }
                                resolved.selection
                            }
                            Err(error) => {
                                self.message = Some(error.to_string());
                                return;
                            }
                        }
                    };
                    if self.files_only && name != "none" {
                        // The profile gives its variants and answers; the units
                        // to deploy are picked by hand
                        let units: Vec<String> = selection.units().map(str::to_string).collect();
                        for unit in units {
                            selection.unselect(&unit);
                        }
                        note = Some(
                            "Files only: pick the units to deploy; the profile gives their variants and answers."
                                .to_string(),
                        );
                    }
                    self.selection = selection;
                    self.goto(Screen::Units);
                    self.message = note;
                }
                _ => {}
            },
            Screen::Units => self.goto(self.after_units()),
            Screen::Variants => self.goto(if self.has_inputs() {
                Screen::Inputs
            } else {
                Screen::Summary
            }),
            Screen::Inputs => {
                let Some(Row::Input { unit, input, .. }) = self.current_row() else {
                    return;
                };
                let Some(decl) = self.registry.unit(&unit).and_then(|u| u.input(&input)) else {
                    return;
                };
                match decl.kind {
                    InputKind::Bool => self.toggle(),
                    InputKind::Choice if !decl.custom => self.cycle(1),
                    kind => {
                        let current = match self.selection.input(&unit, &input) {
                            Some(InputValue::Text(text)) if kind != InputKind::Secret => {
                                text.clone()
                            }
                            _ => String::new(),
                        };
                        self.edit = Some(Edit::Input {
                            unit,
                            input,
                            secret: kind == InputKind::Secret,
                        });
                        self.edit_text = current;
                    }
                }
            }
            Screen::Summary => {
                let plan = self.plan();
                let missing = rows::missing_required(self.registry, &self.selection, &plan);
                if let Some((unit, input)) = missing.first() {
                    self.message = Some(format!(
                        "{unit}: the answer {input} is required (Esc, then Answers)"
                    ));
                    return;
                }
                if plan.is_empty() {
                    self.message = Some("Nothing to run: select units first.".to_string());
                    return;
                }
                self.outcome = Some(Outcome::Run {
                    profile: self.profile.clone(),
                    selection: self.selection.clone(),
                });
            }
        }
    }

    /// The unit counts on the units screen: every unit, or for the files
    /// alone the units with files.
    fn deployable(&self, unit: &str) -> bool {
        !self.files_only
            || self
                .registry
                .unit(unit)
                .is_some_and(|u| !u.files().is_empty())
    }

    /// The screen after the units: the variants, else the answers, else
    /// the summary, when there is something to show.
    fn after_units(&self) -> Screen {
        if self.has_variants() {
            Screen::Variants
        } else if self.has_inputs() {
            Screen::Inputs
        } else {
            Screen::Summary
        }
    }

    /// The plan has variants to pick.
    fn has_variants(&self) -> bool {
        rows::variants(self.registry, &self.selection, &self.plan())
            .iter()
            .any(|r| matches!(r, Row::Variant { .. }))
    }

    /// The plan has questions.
    fn has_inputs(&self) -> bool {
        rows::inputs(self.registry, &self.selection, &self.plan())
            .iter()
            .any(|r| matches!(r, Row::Input { .. }))
    }

    /// The variants of the plan: how many are picked, how many there are.
    fn variant_counts(&self) -> (usize, usize) {
        rows::variants(self.registry, &self.selection, &self.plan())
            .iter()
            .fold((0, 0), |(picked, total), row| match row {
                Row::Section {
                    selected, total: t, ..
                } => (picked + selected, total + t),
                _ => (picked, total),
            })
    }

    /// Delete: the answer under the cursor goes back to its default.
    fn clear_answer(&mut self) {
        if let Some(Row::Input { unit, input, .. }) = self.current_row() {
            self.answer(&unit, &input, String::new());
        }
    }

    /// An answer typed for an input: checked for a choice without custom
    /// values; an empty one removes the answer (the default applies).
    fn answer(&mut self, unit: &str, input: &str, text: String) {
        let Some(decl) = self.registry.unit(unit).and_then(|u| u.input(input)) else {
            return;
        };
        if text.is_empty() {
            if decl.required && decl.default.is_none() {
                self.message = Some(format!("{unit}: {input} is required, it has no default"));
            } else {
                self.selection.unset_input(unit, input);
            }
            return;
        }
        if decl.kind == InputKind::Choice
            && !decl.custom
            && !decl.options.iter().any(|o| o.value == text)
        {
            self.message = Some(format!(
                "{input}: one of {}",
                decl.options
                    .iter()
                    .map(|o| o.value.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            ));
            return;
        }
        self.selection
            .set_input(unit, input, InputValue::Text(text));
    }

    fn save(&mut self, name: &str) {
        let name = name.trim();
        if name.is_empty()
            || !name
                .chars()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
        {
            self.message = Some(
                "A profile name: lower-case letters, digits, dashes and underscores.".to_string(),
            );
            return;
        }
        self.outcome = Some(Outcome::Save {
            name: name.to_string(),
            profile: self.profile.clone(),
            selection: self.selection.clone(),
        });
    }

    fn back(&mut self) {
        if !self.filter.is_empty() {
            self.filter.clear();
            self.clamp_cursor();
            return;
        }
        match self.screen {
            Screen::Profile => self.outcome = Some(Outcome::Quit),
            Screen::Units => self.goto(Screen::Profile),
            Screen::Variants => self.goto(Screen::Units),
            Screen::Inputs => self.goto(if self.has_variants() {
                Screen::Variants
            } else {
                Screen::Units
            }),
            Screen::Summary => self.goto(if self.has_inputs() {
                Screen::Inputs
            } else if self.has_variants() {
                Screen::Variants
            } else {
                Screen::Units
            }),
        }
    }
}

/// The option after (or before) the current one, around the list.
fn next_of(options: &[String], current: &str, step: isize) -> String {
    if options.is_empty() {
        return current.to_string();
    }
    let index = options.iter().position(|o| o == current).unwrap_or(0) as isize;
    let count = options.len() as isize;
    options[((index + step) % count + count) as usize % options.len()].clone()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rows::Shown;
    use crossterm::event::KeyEvent;
    use model::{
        Declarations, Hook, Input, ModuleDeclaration, Package, Platform, Profile, UnitDeclaration,
        Variant,
    };
    use std::path::PathBuf;

    fn registry() -> Registry {
        let unit = |id: &str| UnitDeclaration {
            id: id.into(),
            name: format!("{id} unit"),
            packages: vec![Package {
                name: format!("{id}-pkg"),
                when: None,
            }],
            ..Default::default()
        };
        let mut base = unit("base");
        base.always = true;
        let mut desktop = unit("desktop");
        desktop.requires = vec!["tools".into(), "fonts".into()];
        desktop.variants = vec![Variant {
            id: "theme".into(),
            name: "Theme".into(),
            options: vec!["dark".into(), "light".into()],
            default: None,
        }];
        desktop.files = vec![model::FileEntry {
            source: "x/{theme}".into(),
            target: ".x".into(),
            mode: Default::default(),
            contents: false,
            backup: true,
            permissions: None,
        }];
        let mut tools = unit("tools");
        tools.parent = Some("desktop".into());
        let mut sddm = unit("sddm");
        sddm.parent = Some("desktop".into());
        let mut git = unit("git");
        git.packages.clear();
        git.inputs = vec![
            Input {
                id: "name".into(),
                prompt: "Name".into(),
                required: true,
                ..Default::default()
            },
            Input {
                id: "branch".into(),
                prompt: "Branch".into(),
                default: Some("main".into()),
                ..Default::default()
            },
            Input {
                id: "fido".into(),
                prompt: "FIDO?".into(),
                kind: InputKind::Bool,
                default: Some("false".into()),
                ..Default::default()
            },
        ];
        git.hooks = vec![Hook {
            run: "setup_git".into(),
            when: None,
        }];
        let modules = vec![
            ModuleDeclaration {
                id: "system".into(),
                name: "System".into(),
                about: None,
                root: PathBuf::from("/r"),
                units: vec![base],
                fragments: Vec::new(),
            },
            ModuleDeclaration {
                id: "desktop".into(),
                name: "Desktop".into(),
                about: None,
                root: PathBuf::from("/r"),
                units: vec![desktop, tools, sddm, unit("fonts")],
                fragments: Vec::new(),
            },
            ModuleDeclaration {
                id: "settings".into(),
                name: "Settings".into(),
                about: None,
                root: PathBuf::from("/r"),
                units: vec![git],
                fragments: Vec::new(),
            },
        ];
        let platform = Platform {
            distro: "arch".into(),
            arch: "x86_64".into(),
            ..Default::default()
        };
        Registry::new(Declarations { modules }, &platform).unwrap()
    }

    fn app<'a>(registry: &'a Registry, profiles: &'a Profiles, machine: &'a Machine) -> App<'a> {
        let context = SelectContext {
            registry,
            profiles,
            machine,
            resumable: Some("run of yesterday"),
            private: None,
            ascii: true,
            dry_run: false,
            files_only: false,
            config: &[],
        };
        App::new(&context)
    }

    fn press(app: &mut App, code: KeyCode) {
        app.handle_key(KeyEvent::new(code, KeyModifiers::NONE));
    }

    fn type_text(app: &mut App, text: &str) {
        for c in text.chars() {
            press(app, KeyCode::Char(c));
        }
    }

    #[test]
    fn the_screens_go_from_a_profile_to_a_run() {
        let registry = registry();
        let mut full = Profile {
            name: "full".into(),
            units: vec!["*".into()],
            ..Default::default()
        };
        full.inputs
            .insert("git.name".into(), InputValue::Text("me".into()));
        let profiles = Profiles::new([full]).unwrap();
        let machine = Machine::default();
        let mut app = app(&registry, &profiles, &machine);

        // Profile screen: resume, private, none, full
        assert_eq!(app.rows().len(), 4);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.screen, Screen::Units);
        assert_eq!(app.profile, "full");
        assert!(
            app.selection.contains("desktop")
                && app.selection.contains("sddm")
                && app.selection.contains("git")
        );
        assert!(
            !app.selection.contains("tools"),
            "a required part is not offered"
        );

        // Variants: the theme of the desktop unit, cycled with the arrows
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.screen, Screen::Variants);
        let rows = app.rows();
        assert!(
            matches!(&rows[0], Row::Section { id, .. } if id == "desktop"),
            "{rows:?}"
        );
        assert!(matches!(&rows[1], Row::Variant { option, .. } if option == "dark"));
        assert!(app.status().contains("0 picked"));
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Right);
        assert_eq!(app.selection.variant("desktop", "theme"), Some("light"));
        assert!(app.status().contains("1 picked"));

        // Answers: name from the profile, branch by default, fido toggled
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.screen, Screen::Inputs);
        press(&mut app, KeyCode::Esc);
        assert_eq!(
            app.screen,
            Screen::Variants,
            "back goes through the variants"
        );
        press(&mut app, KeyCode::Enter);
        let rows = app.rows();
        assert!(
            matches!(&rows[1], Row::Input { input, shown: Shown::Value(v), .. } if input == "name" && v == "me")
        );
        assert!(
            matches!(&rows[2], Row::Input { shown: Shown::Value(v), .. } if v == "main (default)")
        );
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Char(' '));
        assert_eq!(
            app.selection.input("git", "fido"),
            Some(&InputValue::Flag(true))
        );

        // Summary, then run
        press(&mut app, KeyCode::Tab);
        assert_eq!(app.screen, Screen::Summary);
        let plan = app.plan();
        assert_eq!(plan.steps()[0].unit(), "base");
        press(&mut app, KeyCode::Enter);
        assert!(matches!(app.outcome, Some(Outcome::Run { ref profile, .. }) if profile == "full"));
    }

    #[test]
    fn a_required_answer_blocks_the_run_until_typed() {
        let registry = registry();
        let profiles = Profiles::new([]).unwrap();
        let machine = Machine::default();
        let mut app = app(&registry, &profiles, &machine);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Enter); // none
        assert_eq!(app.screen, Screen::Units);
        // Select git (the last unit row), go to the answers
        press(&mut app, KeyCode::End);
        press(&mut app, KeyCode::Char(' '));
        assert!(app.selection.contains("git"));
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.screen, Screen::Inputs);
        press(&mut app, KeyCode::Tab);
        press(&mut app, KeyCode::Enter);
        assert!(app.outcome.is_none());
        assert!(
            app.message
                .as_deref()
                .unwrap_or_default()
                .contains("required"),
            "{:?}",
            app.message
        );
        press(&mut app, KeyCode::Esc);
        assert_eq!(app.screen, Screen::Inputs);
        press(&mut app, KeyCode::Down); // the first input row (name)
        press(&mut app, KeyCode::Enter);
        assert!(
            matches!(app.edit, Some(Edit::Input { ref input, secret: false, .. }) if input == "name")
        );
        type_text(&mut app, "me");
        press(&mut app, KeyCode::Enter);
        assert_eq!(
            app.selection.input("git", "name"),
            Some(&InputValue::Text("me".into()))
        );
        press(&mut app, KeyCode::Tab);
        press(&mut app, KeyCode::Enter);
        assert!(matches!(app.outcome, Some(Outcome::Run { .. })));
    }

    #[test]
    fn saving_resuming_and_adding_a_private_repository() {
        let registry = registry();
        let profiles = Profiles::new([]).unwrap();
        let machine = Machine::default();
        let mut app = app(&registry, &profiles, &machine);
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.outcome, Some(Outcome::Resume));

        let mut app = self::app(&registry, &profiles, &machine);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Enter);
        type_text(&mut app, "https://x/y.git");
        press(&mut app, KeyCode::Enter);
        assert_eq!(
            app.outcome,
            Some(Outcome::Private("https://x/y.git".into()))
        );

        let mut app = self::app(&registry, &profiles, &machine);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Enter);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Char(' ')); // desktop, the first unit row
        press(&mut app, KeyCode::Enter); // its variants
        assert_eq!(app.screen, Screen::Variants);
        press(&mut app, KeyCode::Enter); // no answers: the summary
        assert_eq!(app.screen, Screen::Summary);
        press(&mut app, KeyCode::Char('s'));
        type_text(&mut app, "-mine");
        press(&mut app, KeyCode::Enter);
        assert!(matches!(app.outcome, Some(Outcome::Save { ref name, .. }) if name == "mine-mine"));
    }

    #[test]
    fn an_answer_is_cleared_with_delete_or_an_empty_entry() {
        let registry = registry();
        let mut full = Profile {
            name: "full".into(),
            units: vec!["*".into()],
            ..Default::default()
        };
        full.inputs
            .insert("git.name".into(), InputValue::Text("me".into()));
        let profiles = Profiles::new([full]).unwrap();
        let machine = Machine::default();
        let mut app = app(&registry, &profiles, &machine);
        for _ in 0..3 {
            press(&mut app, KeyCode::Down);
        }
        press(&mut app, KeyCode::Enter); // full: the units
        press(&mut app, KeyCode::Enter); // the variants
        press(&mut app, KeyCode::Enter); // the answers
        assert_eq!(app.screen, Screen::Inputs);

        // name is required without default: it cannot be cleared
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Delete);
        assert_eq!(
            app.selection.input("git", "name"),
            Some(&InputValue::Text("me".into()))
        );
        assert!(
            app.message
                .as_deref()
                .unwrap_or_default()
                .contains("required")
        );

        // branch has a default: Delete clears the answer, the default shows
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Enter);
        type_text(&mut app, "dev");
        press(&mut app, KeyCode::Enter);
        assert_eq!(
            app.selection.input("git", "branch"),
            Some(&InputValue::Text("dev".into()))
        );
        press(&mut app, KeyCode::Delete);
        assert_eq!(app.selection.input("git", "branch"), None);
        let rows = app.rows();
        assert!(
            matches!(&rows[2], Row::Input { shown: Shown::Value(v), .. } if v == "main (default)")
        );

        // An emptied entry clears it as well
        press(&mut app, KeyCode::Enter);
        type_text(&mut app, "x");
        press(&mut app, KeyCode::Enter);
        press(&mut app, KeyCode::Enter);
        press(&mut app, KeyCode::Backspace);
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.selection.input("git", "branch"), None);
        assert!(app.message.is_none(), "{:?}", app.message);
    }

    #[test]
    fn scrolling_keeps_a_margin_around_the_cursor() {
        let registry = registry();
        let profiles = Profiles::new([]).unwrap();
        let machine = Machine::default();
        let mut app = app(&registry, &profiles, &machine);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Enter); // none: the units
        let rows = app.rows().len();
        assert_eq!(rows, 6, "{:?}", app.rows());
        assert_eq!(app.scroll(rows, 4), 0);
        for _ in 0..3 {
            press(&mut app, KeyCode::Down);
        }
        assert_eq!(app.cursor(), 3);
        assert_eq!(app.scroll(rows, 4), 1, "a line stays below the cursor");
        press(&mut app, KeyCode::End);
        assert_eq!(app.scroll(rows, 4), rows - 4, "never past the end");
        press(&mut app, KeyCode::Home);
        assert_eq!(app.scroll(rows, 4), 0);
        assert_eq!(app.scroll(rows, 100), 0, "a tall window shows everything");
    }

    #[test]
    fn files_only_plans_the_units_with_files_alone() {
        let registry = registry();
        let mut full = Profile {
            name: "full".into(),
            units: vec!["*".into()],
            ..Default::default()
        };
        full.variants.insert("desktop.theme".into(), "light".into());
        let profiles = Profiles::new([full]).unwrap();
        let machine = Machine::default();
        let context = SelectContext {
            registry: &registry,
            profiles: &profiles,
            machine: &machine,
            resumable: None,
            private: None,
            ascii: true,
            dry_run: false,
            files_only: true,
            config: &[],
        };
        let mut app = App::new(&context);
        press(&mut app, KeyCode::End);
        press(&mut app, KeyCode::Enter); // full: the units
        assert_eq!(app.screen, Screen::Units);
        let rows = app.rows();
        assert_eq!(
            rows.len(),
            2,
            "one module band and the one unit with files: {rows:?}"
        );
        assert!(matches!(&rows[1], Row::Unit { id, .. } if id == "desktop"));
        assert_eq!(
            app.selection.units().count(),
            0,
            "the profile preselects nothing for the files alone"
        );
        assert_eq!(
            app.selection.variant("desktop", "theme"),
            Some("light"),
            "its variants apply"
        );
        assert!(
            app.message
                .as_deref()
                .unwrap_or_default()
                .starts_with("Files only")
        );
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Char(' ')); // desktop
        assert!(app.status().contains("1 selected"), "{}", app.status());
        let plan = app.plan();
        let units: Vec<&str> = plan.steps().iter().map(|s| s.unit()).collect();
        assert_eq!(units, ["desktop"], "only the units with files");
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.screen, Screen::Variants, "the variants still matter");
        press(&mut app, KeyCode::Enter);
        assert_eq!(app.screen, Screen::Summary, "desktop asks nothing");
        assert!(app.status().contains("files only"));
        press(&mut app, KeyCode::Enter);
        assert!(
            matches!(app.outcome, Some(Outcome::Run { .. })),
            "git is out of the plan, its required answer does not matter: {:?}",
            app.message
        );
    }

    #[test]
    fn config_selects_the_units_and_opens_their_variants() {
        let registry = registry();
        let profiles = Profiles::new([]).unwrap();
        let machine = Machine::default();
        let config = ["desktop".to_string()];
        let context = SelectContext {
            registry: &registry,
            profiles: &profiles,
            machine: &machine,
            resumable: None,
            private: None,
            ascii: true,
            dry_run: false,
            files_only: false,
            config: &config,
        };
        let app = App::new(&context);
        assert_eq!(app.screen, Screen::Variants);
        assert!(app.selection.contains("desktop"));
        assert_eq!(app.profile, "none");
        assert!(matches!(&app.rows()[1], Row::Variant { variant, .. } if variant == "theme"));

        // A unit without variants opens on its answers
        let config = ["git".to_string()];
        let app = App::new(&SelectContext {
            config: &config,
            ..context
        });
        assert_eq!(app.screen, Screen::Inputs);
        assert!(app.selection.contains("git"));
    }

    #[test]
    fn the_filter_keeps_sections_of_matching_units() {
        let registry = registry();
        let profiles = Profiles::new([]).unwrap();
        let machine = Machine::default();
        let mut app = app(&registry, &profiles, &machine);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Down);
        press(&mut app, KeyCode::Enter);
        press(&mut app, KeyCode::Char('/'));
        type_text(&mut app, "git");
        let rows = app.rows();
        assert_eq!(rows.len(), 2, "{rows:?}");
        assert!(matches!(&rows[0], Row::Section { id, .. } if id == "settings"));
        assert!(matches!(&rows[1], Row::Unit { id, .. } if id == "git"));
    }
}
