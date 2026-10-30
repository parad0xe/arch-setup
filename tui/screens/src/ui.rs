//! Drawing the screens: a title bar with the steps as tabs, the list on the
//! left, the details of the line under the cursor on the right, a status
//! bar with the keys or the text being typed, and the help popup.

use ratatui::Frame;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::symbols;
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{
    Block, BorderType, Borders, Cell, Clear, LineGauge, List, ListItem, ListState, Padding,
    Paragraph, Row as TableRow, Table, TableState, Tabs, Wrap,
};

use host::Usage;
use model::{InputKind, Reason, Unit};

use crate::app::{App, Edit, Screen};
use crate::rows::{Mark, Row, Shown, Tree};
use crate::theme::Theme;

pub(crate) fn draw(frame: &mut Frame, app: &mut App) {
    let area = frame.area();
    let [bar, body, status] = Layout::vertical([
        Constraint::Length(1),
        Constraint::Min(3),
        Constraint::Length(1),
    ])
    .areas(area);
    draw_title_bar(frame, app, bar);
    match app.screen {
        Screen::Profile => draw_profile(frame, app, body),
        Screen::Summary => draw_summary(frame, app, body),
        Screen::Units | Screen::Variants | Screen::Inputs => {
            draw_list_and_details(frame, app, body)
        }
    }
    draw_status_bar(frame, app, status);
    if app.help {
        draw_help(frame, app, area);
    }
}

fn card<'a>(t: &Theme, title: &str) -> Block<'a> {
    Block::default()
        .borders(Borders::ALL)
        .border_type(if t.ascii {
            BorderType::Plain
        } else {
            BorderType::Rounded
        })
        .border_style(t.border())
        .title(Line::from(Span::styled(format!(" {title} "), t.title())))
        .padding(Padding::horizontal(1))
}

fn plural(count: usize, noun: &str) -> String {
    if count == 1 {
        format!("1 {noun}")
    } else {
        format!("{count} {noun}s")
    }
}

fn gib(bytes: u64) -> String {
    format!("{:.1} GiB", bytes as f64 / (1u64 << 30) as f64)
}

// ==========================================
// TITLE AND STATUS BARS
// ==========================================

fn draw_title_bar(frame: &mut Frame, app: &App, area: Rect) {
    let t = &app.theme;
    let p = &t.palette;
    frame.render_widget(Block::default().style(t.band()), area);
    let [left, right] =
        Layout::horizontal([Constraint::Min(20), Constraint::Length(60)]).areas(area);
    let machine = &app.machine;
    let line = format!(
        " {} {} {} {} {}",
        machine.host,
        t.glyphs.dot,
        machine.system,
        t.glyphs.dot,
        machine
            .virtualization
            .as_deref()
            .map(|v| format!("{v} VM"))
            .or_else(|| machine.bootloader.clone())
            .unwrap_or_else(|| "unknown boot loader".to_string())
    );
    let mut spans = vec![Span::styled(" Arch setup ", t.tag(p.accent))];
    if app.dry_run {
        spans.push(Span::raw(" "));
        spans.push(Span::styled(" DRY RUN ", t.tag(p.yellow)));
    }
    if app.files_only {
        spans.push(Span::raw(" "));
        spans.push(Span::styled(" FILES ONLY ", t.tag(p.cyan)));
    }
    spans.push(Span::styled(line, t.dim()));
    frame.render_widget(Paragraph::new(Line::from(spans)).style(t.band()), left);
    let titles: Vec<Line> = Screen::ALL
        .iter()
        .enumerate()
        .map(|(i, s)| Line::from(format!(" {} {} ", i + 1, s.title())))
        .collect();
    let tabs = Tabs::new(titles)
        .select(app.screen.index())
        .style(t.dim().bg(p.surface))
        .highlight_style(t.tag(p.accent))
        .divider(Span::styled(t.glyphs.dot, t.dim()))
        .padding("", "");
    frame.render_widget(tabs, right);
}

fn draw_status_bar(frame: &mut Frame, app: &App, area: Rect) {
    let t = &app.theme;
    let p = &t.palette;
    let caret = if t.ascii { "_" } else { "▏" };
    let line = match (&app.edit, &app.message) {
        (Some(edit), _) => {
            let (tag, color, help, text) = match edit {
                Edit::Filter => (
                    "Filter",
                    p.cyan,
                    "Enter keeps it, Esc clears it, Space still selects",
                    app.edit_text.clone(),
                ),
                Edit::ProfileName => (
                    "Save as profile",
                    p.green,
                    "Enter saves and quits, Esc cancels",
                    app.edit_text.clone(),
                ),
                Edit::Private => (
                    "Private repository",
                    p.magenta,
                    "an URL (HTTPS) or a folder; Enter adds it, Esc cancels",
                    app.edit_text.clone(),
                ),
                Edit::Input { secret: true, .. } => (
                    "Answer",
                    p.yellow,
                    "typed hidden; Enter keeps it, Esc cancels",
                    "*".repeat(app.edit_text.chars().count()),
                ),
                Edit::Input { .. } => (
                    "Answer",
                    p.yellow,
                    "Enter keeps it, Esc cancels",
                    app.edit_text.clone(),
                ),
            };
            Line::from(vec![
                Span::styled(format!(" {tag} "), t.tag(color)),
                Span::raw(format!(" {text}")),
                Span::styled(caret, t.fg(color)),
                Span::styled(format!("  {help}"), t.dim()),
            ])
        }
        (None, Some(message)) => Line::from(vec![
            Span::styled(" ! ", t.tag(p.yellow)),
            Span::styled(format!(" {message}"), t.fg(p.yellow)),
        ]),
        (None, None) => {
            let mut spans = Vec::new();
            for (key, action) in app.hints() {
                spans.push(Span::raw(" "));
                spans.push(Span::styled(format!(" {key} "), t.key()));
                spans.push(Span::styled(format!(" {action}"), t.dim()));
            }
            if !app.filter.is_empty() {
                spans.push(Span::styled(
                    format!("   filter: {}", app.filter),
                    t.fg(p.cyan),
                ));
            }
            Line::from(spans)
        }
    };
    frame.render_widget(Paragraph::new(line).style(t.band()), area);
}

// ==========================================
// PROFILE: THE MACHINE, THEN THE PROFILES
// ==========================================

fn draw_profile(frame: &mut Frame, app: &mut App, area: Rect) {
    let t = &app.theme;
    let p = &t.palette;
    let machine = app.machine;
    let gauges = machine.memory.is_some() as u16 + machine.disk.is_some() as u16;
    let [panel, rest] =
        Layout::vertical([Constraint::Length(5 + gauges), Constraint::Min(3)]).areas(area);
    let block = card(t, &format!("Machine {} {}", t.glyphs.dot, machine.host));
    let inner = block.inner(panel);
    frame.render_widget(block, panel);

    let [facts, gauge_area] =
        Layout::vertical([Constraint::Length(3), Constraint::Length(gauges)]).areas(inner);
    let [left, right] =
        Layout::horizontal([Constraint::Percentage(45), Constraint::Percentage(55)]).areas(facts);
    let row = |label: &str, value: String| {
        Line::from(vec![
            Span::styled(format!("{label:<8}"), t.fg(p.accent)),
            Span::raw(value),
        ])
    };
    let boot = match (&machine.virtualization, &machine.bootloader) {
        (Some(virt), Some(loader)) => format!("{virt} virtual machine, {loader}"),
        (Some(virt), None) => format!("{virt} virtual machine"),
        (None, Some(loader)) => format!("{loader}, bare metal"),
        (None, None) => "unknown boot loader, bare metal".to_string(),
    };
    frame.render_widget(
        Paragraph::new(vec![
            row("System", machine.system.clone()),
            row("Kernel", machine.kernel.clone()),
            row("Boot", boot),
        ]),
        left,
    );
    frame.render_widget(
        Paragraph::new(vec![
            row("CPU", machine.cpu.clone()),
            row(
                "GPU",
                machine
                    .gpu
                    .clone()
                    .unwrap_or_else(|| "none found".to_string()),
            ),
        ]),
        right,
    );
    let mut y = gauge_area.y;
    for (label, usage) in [("Memory", machine.memory), ("Disk /", machine.disk)] {
        let Some(usage) = usage else { continue };
        draw_gauge(
            frame,
            t,
            Rect {
                x: gauge_area.x,
                y,
                width: gauge_area.width,
                height: 1,
            },
            label,
            usage,
        );
        y += 1;
    }
    draw_list_and_details(frame, app, rest);
}

fn draw_gauge(frame: &mut Frame, t: &Theme, area: Rect, label: &str, usage: Usage) {
    let p = &t.palette;
    let [name, gauge] =
        Layout::horizontal([Constraint::Length(8), Constraint::Min(10)]).areas(area);
    frame.render_widget(
        Paragraph::new(Span::styled(format!("{label:<8}"), t.fg(p.accent))),
        name,
    );
    let ratio = usage.ratio();
    let color = if ratio > 0.9 {
        p.red
    } else if ratio > 0.7 {
        p.yellow
    } else {
        p.green
    };
    let widget = LineGauge::default()
        .ratio(ratio)
        .line_set(if t.ascii {
            symbols::line::NORMAL
        } else {
            symbols::line::THICK
        })
        .filled_style(t.fg(color))
        .unfilled_style(t.fg(p.surface_hi))
        .label(Span::styled(
            format!("{} / {}", gib(usage.used), gib(usage.total)),
            t.dim(),
        ));
    frame.render_widget(widget, gauge);
}

// ==========================================
// LISTS
// ==========================================

/// The columns of a list: the width of a row and of its name column.
struct Cols {
    width: usize,
    name: usize,
}

fn draw_list_and_details(frame: &mut Frame, app: &mut App, area: Rect) {
    let [left, right] =
        Layout::horizontal([Constraint::Percentage(58), Constraint::Percentage(42)]).areas(area);
    let rows = app.rows();
    // The lines inside the borders
    let offset = app.scroll(rows.len(), left.height.saturating_sub(2) as usize);
    let t = &app.theme;
    let name = rows
        .iter()
        .map(|row| match row {
            Row::Unit { id, .. } => id.chars().count(),
            Row::Input { input, .. } => input.chars().count(),
            Row::Variant { variant, .. } => variant.chars().count(),
            Row::Profile { name } => name.chars().count(),
            _ => 0,
        })
        .max()
        .unwrap_or(0)
        .clamp(10, 24);
    let cols = Cols {
        width: left.width.saturating_sub(6) as usize,
        name,
    };
    let items: Vec<ListItem> = rows
        .iter()
        .map(|row| ListItem::new(row_line(app, row, &cols)))
        .collect();
    let block = card(t, app.screen.title()).title_bottom(
        Line::from(Span::styled(format!(" {} ", app.status()), t.dim())).right_aligned(),
    );
    let list = List::new(items)
        .block(block)
        .highlight_style(t.highlight())
        .highlight_symbol(t.glyphs.pointer);
    let mut state = ListState::default()
        .with_offset(offset)
        .with_selected(if rows.is_empty() {
            None
        } else {
            Some(app.cursor())
        });
    frame.render_stateful_widget(list, left, &mut state);

    let text = match rows.get(app.cursor()) {
        Some(row) => details(app, row),
        None => Text::from(Span::styled(
            "Nothing here: the filter matches no line, or nothing is offered.",
            t.dim(),
        )),
    };
    frame.render_widget(
        Paragraph::new(text)
            .wrap(Wrap { trim: false })
            .block(card(t, "Details")),
        right,
    );
}

fn mark_span(t: &Theme, mark: &Mark) -> Span<'static> {
    let p = &t.palette;
    match mark {
        Mark::Selected => Span::styled(
            t.glyphs.selected,
            t.fg(p.green).add_modifier(Modifier::BOLD),
        ),
        Mark::Added(_) => Span::styled(t.glyphs.added, t.fg(p.cyan).add_modifier(Modifier::BOLD)),
        Mark::None => Span::styled(t.glyphs.none, t.dim()),
    }
}

/// A small bar of 6 cells for a count.
fn mini_bar(t: &Theme, count: usize, total: usize) -> String {
    let (full, empty) = if t.ascii { ("#", "-") } else { ("▰", "▱") };
    let cells = 6usize;
    let filled = (count * cells + total / 2)
        .checked_div(total)
        .unwrap_or(0)
        .min(cells);
    format!("{}{}", full.repeat(filled), empty.repeat(cells - filled))
}

fn row_line<'a>(app: &App<'a>, row: &'a Row, cols: &Cols) -> Line<'a> {
    let t = &app.theme;
    let p = &t.palette;
    let g = &t.glyphs;
    let registry = app.registry;
    let name_width = cols.name;
    match row {
        Row::Section {
            name,
            selected,
            total,
            added,
            ..
        } => {
            let counts = if *added > 0 {
                format!("{selected}/{total} +{added}")
            } else {
                format!("{selected}/{total}")
            };
            let color = if selected == total {
                p.green
            } else if *selected > 0 {
                p.yellow
            } else {
                p.dim
            };
            let name_width = cols.width.saturating_sub(1 + 11 + 7).max(8);
            let name: String = name.chars().take(name_width).collect();
            Line::from(vec![
                Span::styled(format!(" {name:<name_width$}"), t.bold().fg(p.magenta)),
                Span::styled(format!("{counts:>10} "), t.dim()),
                Span::styled(mini_bar(t, *selected, *total), t.fg(color)),
                Span::raw(" "),
            ])
            .style(t.band())
        }
        Row::Unit { id, tree, mark } => {
            let name = registry.unit(id).map(Unit::name).unwrap_or("");
            let guide = match tree {
                Tree::None => "",
                Tree::Middle => g.middle,
                Tree::Last => g.last,
            };
            let id_style = match mark {
                Mark::Selected => t.fg(p.fg).add_modifier(Modifier::BOLD),
                Mark::Added(_) => t.fg(p.cyan),
                Mark::None => t.fg(p.fg),
            };
            let mut spans = vec![
                Span::styled(format!("{guide:>4}"), t.dim()),
                mark_span(t, mark),
                Span::styled(format!(" {id:<name_width$} "), id_style),
                Span::styled(
                    name,
                    if matches!(mark, Mark::None) {
                        t.dim()
                    } else {
                        t.fg(p.fg)
                    },
                ),
            ];
            if let Mark::Added(by) = mark {
                spans.push(Span::styled(
                    format!("  {} {by}", if t.ascii { "<-" } else { "←" }),
                    t.fg(p.cyan),
                ));
            }
            Line::from(spans)
        }
        Row::Variant {
            unit,
            variant,
            option,
        } => {
            let name = registry
                .unit(unit)
                .and_then(|u| u.variant(variant))
                .map(|v| v.name.as_str())
                .unwrap_or("");
            Line::from(vec![
                Span::styled(format!("     {variant:<name_width$} "), t.fg(p.fg)),
                Span::styled(format!(" {option} "), t.tag(p.cyan)),
                Span::styled(format!("  {name}"), t.dim()),
            ])
        }
        Row::Input { unit, input, shown } => {
            let prompt = registry
                .unit(unit)
                .and_then(|u| u.input(input))
                .map(|i| i.prompt.as_str())
                .unwrap_or("");
            let value = match shown {
                Shown::Value(value) => Span::styled(format!(" {value} "), t.tag(p.cyan)),
                Shown::Secret { answered: true } => Span::styled(" ****** ", t.tag(p.cyan)),
                Shown::Secret { answered: false } => Span::styled(" not set ", t.tag(p.dim)),
                Shown::Missing { required: true } => Span::styled(" required ", t.tag(p.red)),
                Shown::Missing { required: false } => Span::styled(" empty ", t.tag(p.dim)),
            };
            Line::from(vec![
                Span::styled(format!("     {input:<name_width$} "), t.fg(p.fg)),
                value,
                Span::styled(format!("  {prompt}"), t.dim()),
            ])
        }
        Row::Profile { name } => {
            let about = match app.profiles.get(name) {
                Some(profile) => profile.about.clone().unwrap_or_default(),
                None => "Start from nothing: pick the units yourself".to_string(),
            };
            Line::from(vec![
                Span::styled(
                    format!(" {name:<name_width$}"),
                    t.fg(p.magenta).add_modifier(Modifier::BOLD),
                ),
                Span::styled(format!(" {about}"), t.fg(p.fg)),
            ])
        }
        Row::Resume { description } => Line::from(vec![
            Span::styled(
                format!(" {:<name_width$}", "resume"),
                t.fg(p.yellow).add_modifier(Modifier::BOLD),
            ),
            Span::styled(format!(" {description}"), t.fg(p.fg)),
            Span::styled("  (unfinished)", t.dim()),
        ]),
        Row::Private { source } => Line::from(vec![
            Span::styled(
                format!(" {:<name_width$}", "private"),
                t.fg(p.magenta).add_modifier(Modifier::BOLD),
            ),
            Span::styled(
                format!(
                    " {}",
                    source.clone().unwrap_or_else(|| {
                        "none: Enter adds a private repository (URL or folder)".to_string()
                    })
                ),
                if source.is_some() {
                    t.fg(p.fg)
                } else {
                    t.dim()
                },
            ),
        ]),
        Row::Step { .. } | Row::LeftOut { .. } | Row::Separator(_) => Line::from(""),
    }
}

// ==========================================
// SUMMARY: A TABLE
// ==========================================

fn draw_summary(frame: &mut Frame, app: &mut App, area: Rect) {
    let [left, right] =
        Layout::horizontal([Constraint::Percentage(62), Constraint::Percentage(38)]).areas(area);
    let rows = app.rows();
    // The lines inside the borders, under the header
    let offset = app.scroll(rows.len(), left.height.saturating_sub(3) as usize);
    let t = &app.theme;
    let p = &t.palette;
    let mut number = 0;
    let table_rows: Vec<TableRow> = rows
        .iter()
        .map(|row| match row {
            Row::Step { unit, reason } => {
                number += 1;
                let name = app.registry.unit(unit).map(Unit::name).unwrap_or("");
                let why = match reason {
                    Reason::Always => Span::styled("always", t.dim()),
                    Reason::Picked => Span::styled("picked", t.fg(p.green)),
                    Reason::RequiredBy(by) => Span::styled(
                        format!("{} {by}", if t.ascii { "<-" } else { "←" }),
                        t.fg(p.cyan),
                    ),
                };
                TableRow::new(vec![
                    Cell::from(Span::styled(format!("{number:>3}"), t.dim())),
                    Cell::from(Span::styled(unit.clone(), t.fg(p.fg))),
                    Cell::from(why),
                    Cell::from(Span::styled(name, t.dim())),
                ])
            }
            Row::LeftOut { unit, required_by } => TableRow::new(vec![
                Cell::from(""),
                Cell::from(Span::styled(unit.clone(), t.fg(p.yellow))),
                Cell::from(Span::styled(
                    format!("{} {required_by}", if t.ascii { "<-" } else { "←" }),
                    t.dim(),
                )),
                Cell::from(Span::styled("not for this machine", t.dim())),
            ]),
            Row::Separator(text) => TableRow::new(vec![
                Cell::from(""),
                Cell::from(Span::styled(text.clone(), t.title())),
                Cell::from(""),
                Cell::from(""),
            ]),
            _ => TableRow::new(vec![Cell::from("")]),
        })
        .collect();
    let longest = |f: &dyn Fn(&Row) -> usize| rows.iter().map(f).max().unwrap_or(0) as u16;
    let unit_width = longest(&|r| match r {
        Row::Step { unit, .. } | Row::LeftOut { unit, .. } => unit.chars().count(),
        Row::Separator(s) => s.chars().count(),
        _ => 0,
    })
    .clamp(8, 36);
    let why_width = longest(&|r| match r {
        Row::Step {
            reason: Reason::RequiredBy(by),
            ..
        }
        | Row::LeftOut {
            required_by: by, ..
        } => by.chars().count() + 2,
        Row::Step { .. } => 6,
        _ => 0,
    })
    .clamp(6, 30);
    let widths = [
        Constraint::Length(3),
        Constraint::Length(unit_width),
        Constraint::Length(why_width),
        Constraint::Min(10),
    ];
    let header =
        TableRow::new(["#", "Unit", "Why", "What"].map(|h| Cell::from(Span::styled(h, t.title()))));
    let block = card(t, "Summary").title_bottom(
        Line::from(Span::styled(format!(" {} ", app.status()), t.dim())).right_aligned(),
    );
    let table = Table::new(table_rows, widths)
        .header(header)
        .block(block)
        .row_highlight_style(t.highlight())
        .highlight_symbol(t.glyphs.pointer)
        .column_spacing(1);
    let mut state = TableState::default()
        .with_offset(offset)
        .with_selected(if rows.is_empty() {
            None
        } else {
            Some(app.cursor())
        });
    frame.render_stateful_widget(table, left, &mut state);

    let text = match rows.get(app.cursor()) {
        Some(row) => details(app, row),
        None => Text::from(Span::styled("Nothing to run: select units first.", t.dim())),
    };
    frame.render_widget(
        Paragraph::new(text)
            .wrap(Wrap { trim: false })
            .block(card(t, "Details")),
        right,
    );
}

// ==========================================
// DETAILS
// ==========================================

fn field<'a>(t: &Theme, lines: &mut Vec<Line<'a>>, label: &str, value: String) {
    if !value.is_empty() {
        lines.push(Line::from(vec![
            Span::styled(format!("{label:<12} "), t.fg(t.palette.accent)),
            Span::raw(value),
        ]));
    }
}

fn heading<'a>(t: &Theme, text: &str) -> Line<'a> {
    Line::from(Span::styled(
        text.to_string(),
        t.fg(t.palette.accent).add_modifier(Modifier::UNDERLINED),
    ))
}

/// The paragraphs of a text: its lines joined, a blank line separating.
fn paragraphs(text: &str) -> Vec<String> {
    text.split("\n\n")
        .map(|p| p.split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|p| !p.is_empty())
        .collect()
}

fn details<'a>(app: &'a App, row: &Row) -> Text<'a> {
    let t = &app.theme;
    let p = &t.palette;
    let registry = app.registry;
    let mut lines: Vec<Line> = Vec::new();
    match row {
        Row::Section {
            name,
            selected,
            total,
            ..
        } => {
            lines.push(Line::from(Span::styled(name.clone(), t.title())));
            lines.push(Line::from(""));
            let what = match app.screen {
                Screen::Variants => "picked, the others by default",
                Screen::Inputs => "answered",
                _ => "selected",
            };
            lines.push(Line::from(Span::styled(
                format!("{selected} of {total} {what}."),
                t.dim(),
            )));
            if app.screen == Screen::Units {
                lines.push(Line::from(Span::styled(
                    "Space selects them all, or unselects them all when they all are.",
                    t.dim(),
                )));
            }
        }
        Row::Unit { id, .. } | Row::Step { unit: id, .. } | Row::LeftOut { unit: id, .. } => {
            let mark = if let Row::Unit { mark, .. } = row {
                Some(mark)
            } else {
                None
            };
            unit_details(app, &mut lines, id, mark);
        }
        Row::Variant {
            unit,
            variant,
            option,
        } => {
            let Some(decl) = registry.unit(unit).and_then(|u| u.variant(variant)) else {
                return Text::from(lines);
            };
            lines.push(Line::from(Span::styled(decl.name.clone(), t.title())));
            lines.push(Line::from(""));
            lines.push(heading(
                t,
                &format!("Options ({} to change)", t.glyphs.arrows),
            ));
            for candidate in &decl.options {
                if candidate == option {
                    lines.push(Line::from(vec![
                        Span::styled(format!(" {candidate} "), t.tag(p.cyan)),
                        Span::styled("  chosen", t.dim()),
                    ]));
                } else {
                    lines.push(Line::from(format!(" {candidate}")));
                }
            }
        }
        Row::Input { unit, input, shown } => {
            let Some(decl) = registry.unit(unit).and_then(|u| u.input(input)) else {
                return Text::from(lines);
            };
            lines.push(Line::from(Span::styled(decl.prompt.clone(), t.title())));
            lines.push(Line::from(Span::styled(
                format!("Unit {} {unit}", t.glyphs.dot),
                t.dim(),
            )));
            lines.push(Line::from(""));
            let kind = match decl.kind {
                InputKind::Text => "text",
                InputKind::Bool => "yes or no (Space toggles)",
                InputKind::Secret => "secret: typed hidden, never logged",
                InputKind::Choice if decl.custom => "a choice, or a value of yours (Enter)",
                InputKind::Choice => "a choice",
            };
            field(t, &mut lines, "Kind", kind.to_string());
            if let Some(default) = &decl.default {
                field(t, &mut lines, "Default", default.clone());
            }
            if decl.required {
                field(t, &mut lines, "Required", "yes".to_string());
            }
            if !decl.options.is_empty() {
                lines.push(Line::from(""));
                lines.push(heading(
                    t,
                    &format!("Options ({} to change)", t.glyphs.arrows),
                ));
                for option in &decl.options {
                    let chosen = matches!(shown, Shown::Value(v) if *v == option.value);
                    let label = if option.name == option.value {
                        option.value.clone()
                    } else {
                        format!("{} ({})", option.name, option.value)
                    };
                    if chosen {
                        lines.push(Line::from(vec![
                            Span::styled(format!(" {label} "), t.tag(p.cyan)),
                            Span::styled("  chosen", t.dim()),
                        ]));
                    } else {
                        lines.push(Line::from(format!(" {label}")));
                    }
                }
            }
        }
        Row::Profile { name } => match app.profiles.get(name) {
            Some(profile) => {
                lines.push(Line::from(Span::styled(profile.name.clone(), t.title())));
                lines.push(Line::from(profile.about.clone().unwrap_or_default()));
                lines.push(Line::from(""));
                if let Some(parent) = &profile.extends {
                    field(t, &mut lines, "Extends", parent.clone());
                }
                field(t, &mut lines, "Units", profile.units.join(", "));
                field(t, &mut lines, "Excludes", profile.exclude.join(", "));
                match app.profiles.resolve(name, registry) {
                    Ok(resolved) => {
                        lines.push(Line::from(""));
                        lines.push(Line::from(Span::styled(
                            format!(
                                "{} on this machine",
                                plural(resolved.selection.units().count(), "unit")
                            ),
                            t.fg(p.accent),
                        )));
                        field(
                            t,
                            &mut lines,
                            "",
                            resolved.selection.units().collect::<Vec<_>>().join(", "),
                        );
                        if !resolved.warnings.is_empty() {
                            lines.push(Line::from(""));
                            for warning in &resolved.warnings {
                                lines.push(Line::from(Span::styled(
                                    warning.clone(),
                                    t.fg(p.yellow),
                                )));
                            }
                        }
                    }
                    Err(error) => {
                        lines.push(Line::from(Span::styled(error.to_string(), t.fg(p.red))))
                    }
                }
            }
            None => {
                lines.push(Line::from(Span::styled("none", t.title())));
                lines.push(Line::from("Start from nothing: pick the units yourself."));
            }
        },
        Row::Resume { description } => {
            lines.push(Line::from(Span::styled("resume", t.title())));
            lines.push(Line::from(format!("The {description}.")));
            lines.push(Line::from(""));
            lines.push(Line::from(
                "Enter resumes it: the steps done are skipped, the others run again.",
            ));
            lines.push(Line::from(Span::styled(
                "Starting from a profile instead leaves it aside.",
                t.dim(),
            )));
        }
        Row::Private { source } => {
            lines.push(Line::from(Span::styled("private repository", t.title())));
            match source {
                Some(source) => lines.push(Line::from(format!(
                    "In use: {source}. Its modules are listed after the public ones."
                ))),
                None => {
                    lines.push(Line::from("None yet. A second repository with the same layout, for what stays out of the public one: hosts, mounts, keys, credentials."));
                    lines.push(Line::from(""));
                    lines.push(Line::from(Span::styled("Enter asks for an HTTPS URL (a token is asked next, given to git alone) or a folder such as a USB key.", t.dim())));
                }
            }
        }
        Row::Separator(text) => lines.push(Line::from(text.clone())),
    }
    Text::from(lines)
}

fn unit_details<'a>(app: &'a App, lines: &mut Vec<Line<'a>>, id: &str, mark: Option<&Mark>) {
    let t = &app.theme;
    let p = &t.palette;
    let registry = app.registry;
    let Some(unit) = registry.unit(id) else {
        return;
    };
    lines.push(Line::from(Span::styled(unit.id().to_string(), t.title())));
    lines.push(Line::from(unit.name().to_string()));
    let module = registry
        .modules()
        .iter()
        .find(|m| m.id() == unit.module())
        .map(|m| m.name())
        .unwrap_or("");
    lines.push(Line::from(Span::styled(
        format!("Module {} {module}", t.glyphs.dot),
        t.dim(),
    )));
    if !unit.extended_by().is_empty() {
        lines.push(Line::from(Span::styled(
            format!("Extended by {}", unit.extended_by().join(", ")),
            t.dim(),
        )));
    }
    if let Some(mark) = mark {
        lines.push(Line::from(""));
        lines.push(match mark {
            Mark::Selected => Line::from(Span::styled(" SELECTED ", t.tag(p.green))),
            Mark::Added(by) => Line::from(vec![
                Span::styled(" REQUIRED ", t.tag(p.cyan)),
                Span::styled(format!(" by {by}"), t.fg(p.cyan)),
            ]),
            Mark::None => Line::from(Span::styled(" NOT SELECTED ", t.tag(p.dim))),
        });
    }
    if !unit.available() {
        lines.push(Line::from(Span::styled(
            "Not for this machine.",
            t.fg(p.yellow),
        )));
    }
    for paragraph in paragraphs(unit.about().unwrap_or_default()) {
        lines.push(Line::from(""));
        lines.push(Line::from(paragraph));
    }
    lines.push(Line::from(""));
    lines.push(heading(t, "Does"));
    field(t, lines, "packages", unit.packages().join(", "));
    field(t, lines, "aur", unit.aur().join(", "));
    field(
        t,
        lines,
        "services",
        unit.services()
            .iter()
            .map(|s| s.name.clone())
            .collect::<Vec<_>>()
            .join(", "),
    );
    field(
        t,
        lines,
        "files",
        unit.files()
            .iter()
            .map(|f| {
                format!(
                    "{} {} {}",
                    f.source,
                    if t.ascii { "->" } else { "→" },
                    if f.is_system() {
                        f.target.clone()
                    } else {
                        format!("~/{}", f.target)
                    }
                )
            })
            .collect::<Vec<_>>()
            .join("; "),
    );
    field(
        t,
        lines,
        "hooks",
        unit.hooks().collect::<Vec<_>>().join(", "),
    );
    let parts: Vec<&str> = registry.parts(id).map(Unit::id).collect();
    let required_by: Vec<&str> = registry.required_by(id).map(Unit::id).collect();
    if !unit.requires().is_empty()
        || !unit.after().is_empty()
        || !parts.is_empty()
        || !required_by.is_empty()
    {
        lines.push(Line::from(""));
        lines.push(heading(t, "Links"));
        field(t, lines, "requires", unit.requires().join(", "));
        field(t, lines, "after", unit.after().join(", "));
        field(t, lines, "parts", parts.join(", "));
        field(t, lines, "required by", required_by.join(", "));
    }
    if !unit.inputs().is_empty() {
        lines.push(Line::from(""));
        field(
            t,
            lines,
            "asks",
            unit.inputs()
                .iter()
                .map(|i| i.prompt.clone())
                .collect::<Vec<_>>()
                .join("; "),
        );
    }
    if unit.attended() {
        lines.push(Line::from(Span::styled(
            "Needs the terminal: a tool asks for your attention (skipped with --yes).",
            t.fg(p.yellow),
        )));
    }
    if unit.always() {
        lines.push(Line::from(Span::styled(
            "Runs in every run, first.",
            t.dim(),
        )));
    }
}

// ==========================================
// HELP
// ==========================================

fn draw_help(frame: &mut Frame, app: &App, area: Rect) {
    let t = &app.theme;
    let p = &t.palette;
    let g = &t.glyphs;
    let width = 76.min(area.width.saturating_sub(4));
    let height = 17.min(area.height.saturating_sub(2));
    let popup = Rect {
        x: area.x + (area.width.saturating_sub(width)) / 2,
        y: area.y + (area.height.saturating_sub(height)) / 2,
        width,
        height,
    };
    let key = |k: &str, what: &str| -> Line<'static> {
        Line::from(vec![
            Span::styled(format!(" {k:^12} "), t.key()),
            Span::raw(format!("  {what}")),
        ])
    };
    let text = Text::from(vec![
        key(
            if t.ascii {
                "Up Down j k"
            } else {
                "↑ ↓  j k"
            },
            "move; PgUp/PgDn and g/G jump",
        ),
        key(
            "Space",
            "select or unselect a unit or a whole module; yes/no on an answer",
        ),
        key(g.arrows, "change the option of a variant or of a choice"),
        key("Enter", "next screen; type an answer; on the summary, run"),
        key("Tab", "from the answers to the summary"),
        key(
            "Del",
            "on the answers, clear the answer: its default applies",
        ),
        key("s", "on the summary, save the selection as a profile"),
        key("/", "filter the list (Enter keeps it, Esc clears it)"),
        key("Esc", "previous screen"),
        key("q", "quit without running"),
        Line::from(""),
        Line::from(vec![
            Span::styled(g.selected, t.fg(p.green).add_modifier(Modifier::BOLD)),
            Span::raw(" selected   "),
            Span::styled(g.added, t.fg(p.cyan).add_modifier(Modifier::BOLD)),
            Span::raw(" required by a selected unit   "),
            Span::styled(g.none, t.dim()),
            Span::raw(" not selected"),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            "A saved profile runs with: setup profile <name>",
            t.dim(),
        )),
    ]);
    frame.render_widget(Clear, popup);
    frame.render_widget(
        Paragraph::new(text)
            .wrap(Wrap { trim: false })
            .block(card(t, "Keys").style(Style::new().bg(p.surface).fg(p.fg))),
        popup,
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
    use host::Machine;
    use model::{
        Declarations, Input, ModuleDeclaration, Package, Platform, Profile, Profiles, Registry,
        UnitDeclaration,
    };
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;
    use std::path::PathBuf;

    use crate::SelectContext;

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
        let mut git = unit("git");
        git.inputs = vec![Input {
            id: "name".into(),
            prompt: "Your name".into(),
            required: true,
            ..Default::default()
        }];
        let modules = vec![
            ModuleDeclaration {
                id: "desktop".into(),
                name: "Desktop".into(),
                about: None,
                root: PathBuf::from("/r"),
                units: vec![unit("fonts")],
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

    /// Every screen draws on a small terminal, in both symbol sets, without a
    /// panic and with its title on the first line.
    #[test]
    fn every_screen_draws() {
        let registry = registry();
        let profiles = Profiles::new([Profile {
            name: "full".into(),
            units: vec!["*".into()],
            ..Default::default()
        }])
        .unwrap();
        let machine = Machine {
            host: "box".into(),
            system: "Arch Linux".into(),
            ..Default::default()
        };
        for ascii in [false, true] {
            let context = SelectContext {
                registry: &registry,
                profiles: &profiles,
                machine: &machine,
                resumable: Some("run of today"),
                private: None,
                ascii,
                dry_run: ascii,
                files_only: false,
                config: &[],
            };
            let mut app = App::new(&context);
            let mut terminal = Terminal::new(TestBackend::new(100, 30)).unwrap();
            let mut screens = Vec::new();
            for code in [
                KeyCode::Null,
                KeyCode::End,
                KeyCode::Enter,
                KeyCode::Enter,
                KeyCode::Tab,
                KeyCode::Char('?'),
            ] {
                if code != KeyCode::Null {
                    app.handle_key(KeyEvent::new(code, KeyModifiers::NONE));
                }
                terminal.draw(|frame| draw(frame, &mut app)).unwrap();
                let text = terminal.backend().to_string();
                assert!(
                    text.contains("box"),
                    "the machine is in the title bar:\n{text}"
                );
                assert_eq!(text.contains("DRY RUN"), ascii, "{text}");
                screens.push((app.screen, app.help, text));
            }
            let titles: Vec<_> = screens.iter().map(|(s, _, _)| *s).collect();
            assert_eq!(
                titles,
                [
                    Screen::Profile,
                    Screen::Profile,
                    Screen::Units,
                    Screen::Inputs,
                    Screen::Summary,
                    Screen::Summary
                ]
            );
            assert!(screens[2].2.contains("fonts") && screens[2].2.contains("Desktop"));
            assert!(screens[3].2.contains("Your name") && screens[3].2.contains("required"));
            assert!(screens[4].2.contains("git") && screens[4].2.contains("picked"));
            assert!(screens[5].1 && screens[5].2.contains("Keys"));
        }
    }
}
