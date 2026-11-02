//! The look: a Tokyo Night Moon palette on a true-color terminal, the 16
//! basic colors and plain symbols otherwise (the Linux console). The
//! palette and the symbols are public: the console of the binary shares
//! them.

use ratatui::style::{Color, Modifier, Style};

/// The colors, as RGB, or the basic colors in ascii mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Palette {
    pub fg: Color,
    pub dim: Color,
    pub accent: Color,
    pub cyan: Color,
    pub green: Color,
    pub yellow: Color,
    pub red: Color,
    pub magenta: Color,
    pub surface: Color,
    pub surface_hi: Color,
    pub key_bg: Color,
}

impl Palette {
    pub fn new(ascii: bool) -> Palette {
        if ascii {
            Palette {
                fg: Color::White,
                dim: Color::DarkGray,
                accent: Color::Blue,
                cyan: Color::Cyan,
                green: Color::Green,
                yellow: Color::Yellow,
                red: Color::Red,
                magenta: Color::Magenta,
                surface: Color::Black,
                surface_hi: Color::Blue,
                key_bg: Color::White,
            }
        } else {
            Palette {
                fg: Color::Rgb(0xc8, 0xd3, 0xf5),
                dim: Color::Rgb(0x82, 0x8b, 0xb8),
                accent: Color::Rgb(0x82, 0xaa, 0xff),
                cyan: Color::Rgb(0x86, 0xe1, 0xfc),
                green: Color::Rgb(0xc3, 0xe8, 0x8d),
                yellow: Color::Rgb(0xff, 0xc7, 0x77),
                red: Color::Rgb(0xff, 0x75, 0x7f),
                magenta: Color::Rgb(0xc0, 0x99, 0xff),
                surface: Color::Rgb(0x2f, 0x33, 0x4d),
                surface_hi: Color::Rgb(0x3b, 0x42, 0x61),
                key_bg: Color::Rgb(0x44, 0x4a, 0x73),
            }
        }
    }
}

/// The symbols: a step done, failed, running or skipped, the marks of the
/// lists, the tree guides, the spinner frames.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Glyphs {
    pub ok: &'static str,
    pub fail: &'static str,
    pub run: &'static str,
    pub skip: &'static str,
    pub bar: &'static str,
    pub dot: &'static str,
    pub ellipsis: &'static str,
    pub arrows: &'static str,
    pub selected: &'static str,
    pub added: &'static str,
    pub none: &'static str,
    pub pointer: &'static str,
    pub middle: &'static str,
    pub last: &'static str,
    pub spinner: &'static [&'static str],
}

impl Glyphs {
    pub fn new(ascii: bool) -> Glyphs {
        if ascii {
            Glyphs {
                ok: "OK",
                fail: "!!",
                run: ">>",
                skip: "--",
                bar: "|",
                dot: "*",
                ellipsis: "...",
                arrows: "</>",
                selected: "[x]",
                added: "[+]",
                none: "[ ]",
                pointer: "> ",
                middle: "|- ",
                last: "`- ",
                spinner: &["|", "/", "-", "\\"],
            }
        } else {
            Glyphs {
                ok: "✔",
                fail: "✖",
                run: "▶",
                skip: "↷",
                bar: "│",
                dot: "·",
                ellipsis: "…",
                arrows: "←/→",
                selected: " ● ",
                added: " ◆ ",
                none: " ○ ",
                pointer: "▌ ",
                middle: "├─ ",
                last: "└─ ",
                spinner: &["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
            }
        }
    }
}

/// The styles of the screens.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Theme {
    pub ascii: bool,
    pub palette: Palette,
    pub glyphs: Glyphs,
}

impl Theme {
    pub(crate) fn new(ascii: bool) -> Theme {
        Theme {
            ascii,
            palette: Palette::new(ascii),
            glyphs: Glyphs::new(ascii),
        }
    }

    pub(crate) fn bold(&self) -> Style {
        Style::new().add_modifier(Modifier::BOLD)
    }

    pub(crate) fn dim(&self) -> Style {
        Style::new().fg(self.palette.dim)
    }

    pub(crate) fn title(&self) -> Style {
        Style::new()
            .fg(self.palette.accent)
            .add_modifier(Modifier::BOLD)
    }

    pub(crate) fn border(&self) -> Style {
        Style::new().fg(self.palette.dim)
    }

    pub(crate) fn band(&self) -> Style {
        Style::new().bg(self.palette.surface)
    }

    pub(crate) fn highlight(&self) -> Style {
        Style::new()
            .bg(self.palette.surface_hi)
            .add_modifier(Modifier::BOLD)
    }

    pub(crate) fn key(&self) -> Style {
        Style::new()
            .bg(self.palette.key_bg)
            .fg(self.palette.fg)
            .add_modifier(Modifier::BOLD)
    }

    pub(crate) fn tag(&self, color: Color) -> Style {
        Style::new()
            .bg(color)
            .fg(Color::Black)
            .add_modifier(Modifier::BOLD)
    }

    pub(crate) fn fg(&self, color: Color) -> Style {
        Style::new().fg(color)
    }
}
