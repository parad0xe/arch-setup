//! What the user picked: units, the option of each variant, the answer of
//! each input.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

/// The answer to an input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputValue {
    Text(String),
    Flag(bool),
}

impl fmt::Display for InputValue {
    /// The text, or `1`/`0` for a flag: what the hooks receive.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            InputValue::Text(text) => f.write_str(text),
            InputValue::Flag(true) => f.write_str("1"),
            InputValue::Flag(false) => f.write_str("0"),
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Selection {
    units: BTreeSet<String>,
    /// (unit, variant) -> option
    variants: BTreeMap<(String, String), String>,
    /// (unit, input) -> answer
    inputs: BTreeMap<(String, String), InputValue>,
}

impl Selection {
    pub fn new() -> Selection {
        Selection::default()
    }

    pub fn units(&self) -> impl Iterator<Item = &str> {
        self.units.iter().map(String::as_str)
    }

    pub fn contains(&self, unit: &str) -> bool {
        self.units.contains(unit)
    }

    pub fn select(&mut self, unit: &str) {
        self.units.insert(unit.to_string());
    }

    pub fn unselect(&mut self, unit: &str) {
        self.units.remove(unit);
    }

    /// Selects the unit, or unselects it when it was selected.
    pub fn toggle(&mut self, unit: &str) {
        if !self.units.remove(unit) {
            self.units.insert(unit.to_string());
        }
    }

    /// The option picked for a variant, if any.
    pub fn variant(&self, unit: &str, variant: &str) -> Option<&str> {
        self.variants
            .get(&(unit.to_string(), variant.to_string()))
            .map(String::as_str)
    }

    pub fn set_variant(&mut self, unit: &str, variant: &str, option: &str) {
        self.variants
            .insert((unit.to_string(), variant.to_string()), option.to_string());
    }

    /// Every picked option: (unit, variant, option).
    pub fn variants(&self) -> impl Iterator<Item = (&str, &str, &str)> {
        self.variants
            .iter()
            .map(|((u, v), o)| (u.as_str(), v.as_str(), o.as_str()))
    }

    /// The answer given to an input, if any.
    pub fn input(&self, unit: &str, input: &str) -> Option<&InputValue> {
        self.inputs.get(&(unit.to_string(), input.to_string()))
    }

    pub fn set_input(&mut self, unit: &str, input: &str, value: InputValue) {
        self.inputs
            .insert((unit.to_string(), input.to_string()), value);
    }

    /// Removes an answer: the default applies again, or nothing.
    pub fn unset_input(&mut self, unit: &str, input: &str) {
        self.inputs.remove(&(unit.to_string(), input.to_string()));
    }

    /// Every answer: (unit, input, answer).
    pub fn inputs(&self) -> impl Iterator<Item = (&str, &str, &InputValue)> {
        self.inputs
            .iter()
            .map(|((u, i), v)| (u.as_str(), i.as_str(), v))
    }
}
