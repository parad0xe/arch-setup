//! The platform of a machine, and the conditions the manifests put on them
//! (`when = { arch = "x86_64", vm = false }`).

use std::collections::BTreeMap;

use thiserror::Error;

/// What the manifests may test about the machine. Read by the `host` crate.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Platform {
    /// The distribution: `arch` or `ubuntu`.
    pub distro: String,
    /// `x86_64` or `aarch64`.
    pub arch: String,
    /// `intel`, `amd`, `apple` or `other`.
    pub cpu: String,
    /// The GPU vendors present: `nvidia`, `amd`, `intel`.
    pub gpu: Vec<String>,
    pub vm: bool,
    pub apple_silicon: bool,
    /// `grub`, `systemd-boot` or `none`.
    pub bootloader: String,
    /// The file system types present, e.g. `ntfs`, `btrfs`.
    pub filesystems: Vec<String>,
}

/// What a property holds: a word, a flag, or a list of words.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kind {
    Text,
    Flag,
    List,
}

/// The platform: name, kind, and the accepted words when they are known.
const PROPERTIES: &[(&str, Kind, Option<&[&str]>)] = &[
    ("distro", Kind::Text, Some(&["arch", "ubuntu"])),
    ("arch", Kind::Text, Some(&["x86_64", "aarch64"])),
    ("cpu", Kind::Text, Some(&["intel", "amd", "apple", "other"])),
    ("gpu", Kind::List, Some(&["nvidia", "amd", "intel"])),
    ("vm", Kind::Flag, None),
    ("apple_silicon", Kind::Flag, None),
    (
        "bootloader",
        Kind::Text,
        Some(&["grub", "systemd-boot", "none"]),
    ),
    ("filesystems", Kind::List, None),
];

impl Platform {
    /// The distributions a manifest may name: the words of `distro`.
    pub fn distributions() -> &'static [&'static str] {
        PROPERTIES
            .iter()
            .find(|(name, _, _)| *name == "distro")
            .and_then(|(_, _, words)| *words)
            .unwrap_or_default()
    }
}

/// What a condition expects of a property.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Expected {
    Flag(bool),
    /// One of these words (a list property holds one of them).
    Words(Vec<String>),
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConditionError {
    #[error("unknown property {0}")]
    UnknownProperty(String),
    #[error("the property {0} is true or false")]
    FlagExpected(String),
    #[error("the property {0} is a word, not true or false")]
    WordExpected(String),
    #[error("the property {property} is never {value}")]
    UnknownWord { property: String, value: String },
    #[error("a condition needs at least one property")]
    Empty,
}

/// Conditions on the platform, all of which must hold.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Condition(BTreeMap<String, Expected>);

impl Condition {
    /// Checks the property names, kinds and words.
    pub fn new(
        terms: impl IntoIterator<Item = (String, Expected)>,
    ) -> Result<Condition, ConditionError> {
        let mut checked = BTreeMap::new();
        for (property, expected) in terms {
            let (_, kind, words) = PROPERTIES
                .iter()
                .find(|(name, _, _)| *name == property)
                .ok_or_else(|| ConditionError::UnknownProperty(property.clone()))?;
            match (&expected, kind) {
                (Expected::Flag(_), Kind::Flag) => {}
                (Expected::Flag(_), _) => return Err(ConditionError::WordExpected(property)),
                (Expected::Words(_), Kind::Flag) => {
                    return Err(ConditionError::FlagExpected(property));
                }
                (Expected::Words(values), _) => {
                    if let Some(words) = words {
                        if let Some(value) = values.iter().find(|v| !words.contains(&v.as_str())) {
                            return Err(ConditionError::UnknownWord {
                                property,
                                value: value.clone(),
                            });
                        }
                    }
                }
            }
            checked.insert(property, expected);
        }
        if checked.is_empty() {
            return Err(ConditionError::Empty);
        }
        Ok(Condition(checked))
    }

    /// Whether every term holds on the machine.
    pub fn holds(&self, platform: &Platform) -> bool {
        self.0
            .iter()
            .all(|(property, expected)| match (property.as_str(), expected) {
                ("vm", Expected::Flag(flag)) => platform.vm == *flag,
                ("apple_silicon", Expected::Flag(flag)) => platform.apple_silicon == *flag,
                ("distro", Expected::Words(words)) => words.contains(&platform.distro),
                ("arch", Expected::Words(words)) => words.contains(&platform.arch),
                ("cpu", Expected::Words(words)) => words.contains(&platform.cpu),
                ("bootloader", Expected::Words(words)) => words.contains(&platform.bootloader),
                ("gpu", Expected::Words(words)) => platform.gpu.iter().any(|g| words.contains(g)),
                ("filesystems", Expected::Words(words)) => {
                    platform.filesystems.iter().any(|f| words.contains(f))
                }
                _ => false,
            })
    }

    /// The terms, by property name.
    pub fn terms(&self) -> impl Iterator<Item = (&str, &Expected)> {
        self.0
            .iter()
            .map(|(property, expected)| (property.as_str(), expected))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn words(property: &str, values: &[&str]) -> (String, Expected) {
        (
            property.to_string(),
            Expected::Words(values.iter().map(|v| v.to_string()).collect()),
        )
    }

    fn flag(property: &str, value: bool) -> (String, Expected) {
        (property.to_string(), Expected::Flag(value))
    }

    fn machine() -> Platform {
        Platform {
            distro: "arch".into(),
            arch: "x86_64".into(),
            cpu: "intel".into(),
            gpu: vec!["nvidia".into()],
            vm: false,
            apple_silicon: false,
            bootloader: "grub".into(),
            filesystems: vec!["ext4".into(), "ntfs".into()],
        }
    }

    #[test]
    fn conditions_hold_on_the_platform() {
        let platform = machine();
        assert!(
            Condition::new([words("arch", &["x86_64"]), flag("vm", false)])
                .unwrap()
                .holds(&platform)
        );
        assert!(
            Condition::new([words("gpu", &["nvidia"])])
                .unwrap()
                .holds(&platform)
        );
        assert!(
            Condition::new([words("filesystems", &["ntfs"])])
                .unwrap()
                .holds(&platform)
        );
        assert!(
            Condition::new([words("cpu", &["amd", "intel"])])
                .unwrap()
                .holds(&platform)
        );
        assert!(
            Condition::new([words("distro", &["arch"])])
                .unwrap()
                .holds(&platform)
        );
        assert!(
            !Condition::new([words("distro", &["ubuntu"])])
                .unwrap()
                .holds(&platform)
        );
        assert!(
            !Condition::new([words("arch", &["aarch64"])])
                .unwrap()
                .holds(&platform)
        );
        assert!(!Condition::new([flag("vm", true)]).unwrap().holds(&platform));
        assert!(
            !Condition::new([words("gpu", &["amd"])])
                .unwrap()
                .holds(&platform)
        );
    }

    #[test]
    fn conditions_are_checked() {
        assert_eq!(
            Condition::new([words("color", &["blue"])]).unwrap_err(),
            ConditionError::UnknownProperty("color".into())
        );
        assert_eq!(
            Condition::new([words("vm", &["yes"])]).unwrap_err(),
            ConditionError::FlagExpected("vm".into())
        );
        assert_eq!(
            Condition::new([flag("arch", true)]).unwrap_err(),
            ConditionError::WordExpected("arch".into())
        );
        assert_eq!(
            Condition::new([words("arch", &["riscv"])]).unwrap_err(),
            ConditionError::UnknownWord {
                property: "arch".into(),
                value: "riscv".into()
            }
        );
        assert!(
            Condition::new([words("filesystems", &["zfs"])]).is_ok(),
            "file system types are open"
        );
        assert_eq!(Condition::new([]).unwrap_err(), ConditionError::Empty);
    }
}
