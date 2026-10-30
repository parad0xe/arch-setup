//! What the setup has to say to Windows.

use std::process::ExitCode;

use crate::console::{Console, Line, Tone};

const LINES: &[&str] = &[
    "",
    "W I N D O W S ?   N O .",
    "",
    "This setup turns a fresh Arch Linux into a Hyprland desktop.",
    "There is nothing here for Windows: go get lost somewhere else,",
    "and come back once a real system boots this machine.",
    "",
];

/// Prints the message in a frame and refuses to go further.
pub fn windows(console: &mut Console, ascii: bool) -> ExitCode {
    let (top, bottom, side, bar) = if ascii {
        ("+", "+", "|", "-")
    } else {
        ("╭", "╰", "│", "─")
    };
    let (top_right, bottom_right) = if ascii { ("+", "+") } else { ("╮", "╯") };
    let width = LINES.iter().map(|l| l.chars().count()).max().unwrap_or(0) + 6;
    let rule = bar.repeat(width);
    console.blank();
    console.say(Line::new().push(Tone::Fail, format!("  {top}{rule}{top_right}")));
    for line in LINES {
        let padding = " ".repeat(width - 6 - line.chars().count());
        console.say(
            Line::new()
                .push(Tone::Fail, format!("  {side}   "))
                .push(Tone::Bold, (*line).to_string())
                .push(Tone::Fail, format!("{padding}   {side}")),
        );
    }
    console.say(Line::new().push(Tone::Fail, format!("  {bottom}{rule}{bottom_right}")));
    console.blank();
    ExitCode::FAILURE
}
