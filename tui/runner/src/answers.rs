//! The option of each variant and the answer of each input, as the hooks
//! receive them: plain strings, flags as `1` or `0`.

use std::collections::BTreeMap;

use model::{InputKind, InputValue, Registry, Selection, Unit};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Answers {
    /// (unit, variant) -> option
    variants: BTreeMap<(String, String), String>,
    /// (unit, input) -> value
    inputs: BTreeMap<(String, String), String>,
}

impl Answers {
    /// The answers of a selection, completed with the defaults of the units
    /// of the registry: the default option of a variant, the default of an
    /// input. An input without default stays unanswered.
    pub fn from_selection(registry: &Registry, selection: &Selection) -> Answers {
        let mut answers = Answers::default();
        for unit in registry.units() {
            for variant in unit.variants() {
                let option = selection
                    .variant(unit.id(), &variant.id)
                    .unwrap_or(default_option(variant));
                answers.set_variant(unit.id(), &variant.id, option);
            }
            for input in unit.inputs() {
                let value = match selection.input(unit.id(), &input.id) {
                    Some(value) => Some(value.to_string()),
                    None => input
                        .default
                        .as_deref()
                        .map(|d| default_text(input.kind, d)),
                };
                if let Some(value) = value {
                    answers.set_input(unit.id(), &input.id, &value);
                }
            }
        }
        answers
    }

    /// The answers a run recorded (its secrets were left out).
    pub fn from_recorded(
        variants: impl IntoIterator<Item = (String, String, String)>,
        inputs: impl IntoIterator<Item = (String, String, String)>,
    ) -> Answers {
        let mut answers = Answers::default();
        for (unit, variant, option) in variants {
            answers.set_variant(&unit, &variant, &option);
        }
        for (unit, input, value) in inputs {
            answers.set_input(&unit, &input, &value);
        }
        answers
    }

    pub fn set_variant(&mut self, unit: &str, variant: &str, option: &str) {
        self.variants
            .insert((unit.to_string(), variant.to_string()), option.to_string());
    }

    pub fn set_input(&mut self, unit: &str, input: &str, value: &str) {
        self.inputs
            .insert((unit.to_string(), input.to_string()), value.to_string());
    }

    pub fn variant(&self, unit: &str, variant: &str) -> Option<&str> {
        self.variants
            .get(&(unit.to_string(), variant.to_string()))
            .map(String::as_str)
    }

    pub fn input(&self, unit: &str, input: &str) -> Option<&str> {
        self.inputs
            .get(&(unit.to_string(), input.to_string()))
            .map(String::as_str)
    }

    /// The variants of a unit: (variant, option).
    pub fn variants_of<'a>(
        &'a self,
        unit: &'a str,
    ) -> impl Iterator<Item = (&'a str, &'a str)> + 'a {
        self.variants
            .iter()
            .filter(move |((u, _), _)| u == unit)
            .map(|((_, v), o)| (v.as_str(), o.as_str()))
    }

    /// The inputs of a unit: (input, value).
    pub fn inputs_of<'a>(&'a self, unit: &'a str) -> impl Iterator<Item = (&'a str, &'a str)> + 'a {
        self.inputs
            .iter()
            .filter(move |((u, _), _)| u == unit)
            .map(|((_, i), v)| (i.as_str(), v.as_str()))
    }

    /// Every variant: (unit, variant, option), for the run folder.
    pub fn variants(&self) -> Vec<(String, String, String)> {
        self.variants
            .iter()
            .map(|((u, v), o)| (u.clone(), v.clone(), o.clone()))
            .collect()
    }

    /// Every input but the secrets of the units: (unit, input, value), for
    /// the run folder.
    pub fn inputs_without_secrets(&self, registry: &Registry) -> Vec<(String, String, String)> {
        self.inputs
            .iter()
            .filter(|((unit, input), _)| {
                registry
                    .unit(unit)
                    .and_then(|u| u.input(input))
                    .is_none_or(|i| i.kind != InputKind::Secret)
            })
            .map(|((u, i), v)| (u.clone(), i.clone(), v.clone()))
            .collect()
    }

    /// The inputs of a unit that have no answer and no default: to ask.
    pub fn missing<'a>(&self, unit: &'a Unit) -> Vec<&'a model::Input> {
        unit.inputs()
            .iter()
            .filter(|input| self.input(unit.id(), &input.id).is_none())
            .collect()
    }
}

/// The option used when none is picked: `default` when the options have
/// it, else the first.
pub fn default_option(variant: &model::Variant) -> &str {
    variant
        .default
        .as_deref()
        .or_else(|| {
            variant
                .options
                .iter()
                .find(|o| *o == "default")
                .map(String::as_str)
        })
        .or_else(|| variant.options.first().map(String::as_str))
        .unwrap_or_default()
}

/// A declared default as the hooks receive it.
fn default_text(kind: InputKind, default: &str) -> String {
    match kind {
        InputKind::Bool => InputValue::Flag(default == "true").to_string(),
        _ => default.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use model::{
        Declarations, FileEntry, Input, ModuleDeclaration, Package, Platform, UnitDeclaration,
        Variant,
    };

    fn registry() -> Registry {
        let unit = UnitDeclaration {
            id: "shell".into(),
            name: "Shell".into(),
            packages: vec![Package {
                name: "zsh".into(),
                when: None,
            }],
            files: vec![FileEntry {
                source: "zshrc/{zshrc}.zsh".into(),
                target: ".zshrc".into(),
                mode: Default::default(),
                contents: false,
                backup: true,
                permissions: None,
            }],
            variants: vec![Variant {
                id: "zshrc".into(),
                name: "Zsh".into(),
                options: vec!["mine".into(), "default".into()],
                default: None,
            }],
            inputs: vec![
                Input {
                    id: "fido".into(),
                    prompt: "FIDO?".into(),
                    kind: InputKind::Bool,
                    default: Some("false".into()),
                    ..Default::default()
                },
                Input {
                    id: "email".into(),
                    prompt: "Email".into(),
                    required: true,
                    ..Default::default()
                },
                Input {
                    id: "pass".into(),
                    prompt: "Pass".into(),
                    kind: InputKind::Secret,
                    ..Default::default()
                },
            ],
            ..Default::default()
        };
        let module = ModuleDeclaration {
            id: "m".into(),
            name: "M".into(),
            about: None,
            root: std::path::PathBuf::from("/repo"),
            units: vec![unit],
            fragments: Vec::new(),
        };
        Registry::new(
            Declarations {
                modules: vec![module],
            },
            &Platform {
                distro: "arch".into(),
                arch: "x86_64".into(),
                ..Default::default()
            },
        )
        .unwrap()
    }

    #[test]
    fn answers_complete_the_selection_with_the_defaults() {
        let reg = registry();
        let mut sel = Selection::new();
        sel.set_input("shell", "pass", InputValue::Text("secret".into()));
        let answers = Answers::from_selection(&reg, &sel);
        assert_eq!(
            answers.variant("shell", "zshrc"),
            Some("default"),
            "the option named default wins over the first"
        );
        assert_eq!(
            answers.input("shell", "fido"),
            Some("0"),
            "a bool default becomes 1 or 0"
        );
        assert_eq!(
            answers.input("shell", "email"),
            None,
            "no default: unanswered"
        );
        assert_eq!(
            answers
                .missing(reg.unit("shell").unwrap())
                .iter()
                .map(|i| i.id.as_str())
                .collect::<Vec<_>>(),
            ["email"]
        );
        let recorded = answers.inputs_without_secrets(&reg);
        assert!(
            recorded.iter().all(|(_, input, _)| input != "pass"),
            "{recorded:?}"
        );
        assert_eq!(
            answers.variants(),
            [(
                "shell".to_string(),
                "zshrc".to_string(),
                "default".to_string()
            )]
        );

        let back = Answers::from_recorded(answers.variants(), recorded);
        assert_eq!(back.variant("shell", "zshrc"), Some("default"));
        assert_eq!(back.input("shell", "pass"), None);
    }
}
