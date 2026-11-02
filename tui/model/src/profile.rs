//! The profiles: named selections, composed with `extends`.

use std::collections::BTreeMap;

use thiserror::Error;

use crate::declarations::InputKind;
use crate::registry::Registry;
use crate::selection::{InputValue, Selection};

/// A profile as read from its file.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Profile {
    /// The file name.
    pub name: String,
    pub about: Option<String>,
    /// Another profile, resolved first.
    pub extends: Option<String>,
    /// Unit ids or patterns added to the selection.
    pub units: Vec<String>,
    /// Unit ids or patterns removed from it, after `units`.
    pub exclude: Vec<String>,
    /// "unit.variant" -> option
    pub variants: BTreeMap<String, String>,
    /// "unit.input" -> answer
    pub inputs: BTreeMap<String, InputValue>,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ProfileError {
    #[error("profile {0}: declared twice")]
    Duplicate(String),
    #[error("unknown profile {0}")]
    Unknown(String),
    #[error("the profiles extend each other in a cycle: {}", .0.join(" -> "))]
    ExtendsCycle(Vec<String>),
    #[error("profile {profile}: {key} is not unit.{what}")]
    BadKey {
        profile: String,
        key: String,
        what: &'static str,
    },
    #[error("profile {profile}: {key} names an unknown unit")]
    UnknownUnit { profile: String, key: String },
    #[error("profile {profile}: {key} names an unknown variant")]
    UnknownVariant { profile: String, key: String },
    #[error("profile {profile}: {key} has no option {option}")]
    UnknownOption {
        profile: String,
        key: String,
        option: String,
    },
    #[error("profile {profile}: {key} names an unknown input")]
    UnknownInput { profile: String, key: String },
    #[error("profile {profile}: {pattern} is not a pattern: {reason}")]
    BadPattern {
        profile: String,
        pattern: String,
        reason: String,
    },
    #[error("profile {profile}: {key} wants a {expected}")]
    InputType {
        profile: String,
        key: String,
        expected: &'static str,
    },
}

/// A profile resolved into a selection.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Resolved {
    pub selection: Selection,
    /// Patterns matching no offered unit.
    pub warnings: Vec<String>,
}

/// The profiles known, by name.
#[derive(Debug, Clone, Default)]
pub struct Profiles(BTreeMap<String, Profile>);

impl Profiles {
    /// Keeps the profiles by name; a name given twice is an error (a user
    /// profile replacing a repository one is settled by the reader).
    pub fn new(profiles: impl IntoIterator<Item = Profile>) -> Result<Profiles, ProfileError> {
        let mut map = BTreeMap::new();
        for profile in profiles {
            if map.contains_key(&profile.name) {
                return Err(ProfileError::Duplicate(profile.name));
            }
            map.insert(profile.name.clone(), profile);
        }
        Ok(Profiles(map))
    }

    pub fn names(&self) -> impl Iterator<Item = &str> {
        self.0.keys().map(String::as_str)
    }

    pub fn get(&self, name: &str) -> Option<&Profile> {
        self.0.get(name)
    }

    pub fn iter(&self) -> impl Iterator<Item = &Profile> {
        self.0.values()
    }

    /// The profile and the ones it extends, the root first.
    fn chain(&self, name: &str) -> Result<Vec<&Profile>, ProfileError> {
        let mut chain = Vec::new();
        let mut current = name;
        loop {
            let profile = self
                .get(current)
                .ok_or_else(|| ProfileError::Unknown(current.to_string()))?;
            if chain.iter().any(|p: &&Profile| p.name == profile.name) {
                let mut cycle: Vec<String> = chain.iter().map(|p| p.name.clone()).collect();
                cycle.push(profile.name.clone());
                return Err(ProfileError::ExtendsCycle(cycle));
            }
            chain.push(profile);
            match &profile.extends {
                Some(parent) => current = parent,
                None => break,
            }
        }
        chain.reverse();
        Ok(chain)
    }

    /// Resolves a profile on a registry: the units its chain adds and
    /// removes, among the offered ones, and the variants and inputs, the
    /// extending profile overriding.
    pub fn resolve(&self, name: &str, registry: &Registry) -> Result<Resolved, ProfileError> {
        let mut selection = Selection::new();
        let mut warnings = Vec::new();
        for profile in self.chain(name)? {
            for pattern in &profile.units {
                let matcher = compile(&profile.name, pattern)?;
                let literal = !pattern.contains(['*', '?', '[']);
                let mut matched = false;
                for unit in registry
                    .units()
                    .filter(|u| u.offered() && matcher.matches(u.id()))
                {
                    matched = true;
                    // Exclusive parts: a name picks one, a pattern keeps the default
                    if let Some((_, choice)) = registry.choice_of(unit.id()) {
                        if literal {
                            for part in &choice.parts {
                                selection.unselect(part);
                            }
                        } else if choice.default != unit.id() {
                            continue;
                        }
                    }
                    selection.select(unit.id());
                }
                if !matched {
                    warnings.push(format!(
                        "profile {}: {pattern} matches no offered unit",
                        profile.name
                    ));
                }
            }
            for pattern in &profile.exclude {
                let matcher = compile(&profile.name, pattern)?;
                let ids: Vec<String> = selection
                    .units()
                    .filter(|id| matcher.matches(id))
                    .map(str::to_string)
                    .collect();
                if ids.is_empty() {
                    warnings.push(format!(
                        "profile {}: {pattern} excludes nothing",
                        profile.name
                    ));
                }
                for id in ids {
                    selection.unselect(&id);
                }
            }
            for (key, option) in &profile.variants {
                let (unit_id, variant_id) = split_key(&profile.name, key, "variant")?;
                let unit = registry
                    .unit(unit_id)
                    .ok_or_else(|| ProfileError::UnknownUnit {
                        profile: profile.name.clone(),
                        key: key.clone(),
                    })?;
                let variant =
                    unit.variant(variant_id)
                        .ok_or_else(|| ProfileError::UnknownVariant {
                            profile: profile.name.clone(),
                            key: key.clone(),
                        })?;
                if !variant.options.contains(option) {
                    return Err(ProfileError::UnknownOption {
                        profile: profile.name.clone(),
                        key: key.clone(),
                        option: option.clone(),
                    });
                }
                selection.set_variant(unit_id, variant_id, option);
            }
            for (key, value) in &profile.inputs {
                let (unit_id, input_id) = split_key(&profile.name, key, "input")?;
                let unit = registry
                    .unit(unit_id)
                    .ok_or_else(|| ProfileError::UnknownUnit {
                        profile: profile.name.clone(),
                        key: key.clone(),
                    })?;
                let input = unit
                    .input(input_id)
                    .ok_or_else(|| ProfileError::UnknownInput {
                        profile: profile.name.clone(),
                        key: key.clone(),
                    })?;
                let expected = match (input.kind, value) {
                    (InputKind::Bool, InputValue::Flag(_)) => None,
                    (InputKind::Bool, InputValue::Text(_)) => Some("true or false"),
                    (_, InputValue::Flag(_)) => Some("text"),
                    (_, InputValue::Text(_)) => None,
                };
                if let Some(expected) = expected {
                    return Err(ProfileError::InputType {
                        profile: profile.name.clone(),
                        key: key.clone(),
                        expected,
                    });
                }
                selection.set_input(unit_id, input_id, value.clone());
            }
        }
        Ok(Resolved {
            selection,
            warnings,
        })
    }
}

/// A unit pattern of a profile (`*`, `?`, `[...]`).
fn compile(profile: &str, pattern: &str) -> Result<glob::Pattern, ProfileError> {
    glob::Pattern::new(pattern).map_err(|error| ProfileError::BadPattern {
        profile: profile.to_string(),
        pattern: pattern.to_string(),
        reason: error.msg.to_string(),
    })
}

fn split_key<'a>(
    profile: &str,
    key: &'a str,
    what: &'static str,
) -> Result<(&'a str, &'a str), ProfileError> {
    match key.split_once('.') {
        Some((unit, rest)) if !unit.is_empty() && !rest.is_empty() && !rest.contains('.') => {
            Ok((unit, rest))
        }
        _ => Err(ProfileError::BadKey {
            profile: profile.to_string(),
            key: key.to_string(),
            what,
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::declarations::{Input, InputKind, Variant};
    use crate::registry::tests::{declarations, module, platform, unit};

    fn registry() -> Registry {
        let mut decls = declarations();
        let mut themed = unit("themed");
        themed.files = vec![crate::declarations::FileEntry {
            source: ".config/t/{theme}".into(),
            target: ".config/t".into(),
            mode: Default::default(),
            contents: false,
            backup: true,
            permissions: None,
        }];
        themed.variants = vec![Variant {
            id: "theme".into(),
            name: "Theme".into(),
            options: vec!["light".into(), "dark".into()],
            default: None,
        }];
        themed.inputs = vec![
            Input {
                id: "email".into(),
                prompt: "Email".into(),
                ..Default::default()
            },
            Input {
                id: "fido".into(),
                prompt: "FIDO?".into(),
                kind: InputKind::Bool,
                ..Default::default()
            },
        ];
        decls.modules.push(module("gamma", vec![themed]));
        Registry::new(decls, &platform()).unwrap()
    }

    fn profile(name: &str, extends: Option<&str>, units: &[&str], exclude: &[&str]) -> Profile {
        Profile {
            name: name.into(),
            extends: extends.map(str::to_string),
            units: units.iter().map(|u| u.to_string()).collect(),
            exclude: exclude.iter().map(|u| u.to_string()).collect(),
            ..Default::default()
        }
    }

    #[test]
    fn a_profile_chain_adds_removes_and_overrides() {
        let reg = registry();
        let mut full = profile("full", None, &["*"], &[]);
        full.variants.insert("themed.theme".into(), "light".into());
        let mut mine = profile("mine", Some("full"), &[], &["slow", "ex*"]);
        mine.variants.insert("themed.theme".into(), "dark".into());
        mine.inputs
            .insert("themed.email".into(), InputValue::Text("me@x".into()));
        mine.inputs
            .insert("themed.fido".into(), InputValue::Flag(true));
        let profiles = Profiles::new([full, mine]).unwrap();

        let resolved = profiles.resolve("mine", &reg).unwrap();
        let units: Vec<&str> = resolved.selection.units().collect();
        assert_eq!(
            units,
            ["early", "elem", "late", "quick", "themed"],
            "offered units, minus the excluded ones; always and unavailable ones are not listed"
        );
        assert_eq!(
            resolved.selection.variant("themed", "theme"),
            Some("dark"),
            "the extending profile overrides"
        );
        assert_eq!(
            resolved.selection.input("themed", "email"),
            Some(&InputValue::Text("me@x".into()))
        );
        assert_eq!(
            resolved.selection.input("themed", "fido"),
            Some(&InputValue::Flag(true))
        );
        assert!(resolved.warnings.is_empty());

        let full = profiles.resolve("full", &reg).unwrap();
        assert_eq!(full.selection.variant("themed", "theme"), Some("light"));
        assert!(full.selection.contains("slow"));
    }

    #[test]
    fn patterns_matching_nothing_are_warned_about() {
        let reg = registry();
        let profiles =
            Profiles::new([profile("p", None, &["nothing-*", "quick"], &["ghost"])]).unwrap();
        let resolved = profiles.resolve("p", &reg).unwrap();
        assert_eq!(resolved.selection.units().collect::<Vec<_>>(), ["quick"]);
        assert_eq!(
            resolved.warnings,
            [
                "profile p: nothing-* matches no offered unit",
                "profile p: ghost excludes nothing"
            ]
        );
    }

    #[test]
    fn profiles_are_checked() {
        let reg = registry();
        assert_eq!(
            Profiles::new([profile("a", None, &[], &[]), profile("a", None, &[], &[])])
                .unwrap_err(),
            ProfileError::Duplicate("a".into())
        );
        let profiles = Profiles::new([
            profile("a", Some("b"), &[], &[]),
            profile("b", Some("a"), &[], &[]),
        ])
        .unwrap();
        assert_eq!(
            profiles.resolve("a", &reg).unwrap_err(),
            ProfileError::ExtendsCycle(vec!["a".into(), "b".into(), "a".into()])
        );
        assert_eq!(
            Profiles::new([profile("a", Some("zzz"), &[], &[])])
                .unwrap()
                .resolve("a", &reg)
                .unwrap_err(),
            ProfileError::Unknown("zzz".into())
        );

        let mut bad = profile("bad", None, &[], &[]);
        bad.variants.insert("themed.theme".into(), "neon".into());
        assert_eq!(
            Profiles::new([bad])
                .unwrap()
                .resolve("bad", &reg)
                .unwrap_err(),
            ProfileError::UnknownOption {
                profile: "bad".into(),
                key: "themed.theme".into(),
                option: "neon".into()
            }
        );
        let mut bad = profile("bad", None, &[], &[]);
        bad.inputs
            .insert("themed.fido".into(), InputValue::Text("yes".into()));
        assert_eq!(
            Profiles::new([bad])
                .unwrap()
                .resolve("bad", &reg)
                .unwrap_err(),
            ProfileError::InputType {
                profile: "bad".into(),
                key: "themed.fido".into(),
                expected: "true or false"
            }
        );
        let mut bad = profile("bad", None, &[], &[]);
        bad.variants.insert("theme".into(), "dark".into());
        assert_eq!(
            Profiles::new([bad])
                .unwrap()
                .resolve("bad", &reg)
                .unwrap_err(),
            ProfileError::BadKey {
                profile: "bad".into(),
                key: "theme".into(),
                what: "variant"
            }
        );
    }
}
