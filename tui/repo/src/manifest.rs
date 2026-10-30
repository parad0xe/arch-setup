//! A module manifest (`modules/<module>/module.toml`): its TOML form, and
//! its conversion into declarations: units, and fragments extending or
//! overriding units of modules read before.

use std::collections::BTreeMap;
use std::path::Path;

use model::{
    Choice, Condition, Expected, FileEntry, Fragment, Hook, Input, InputKind, InputOption, Merge,
    Mode, ModuleDeclaration, Package, Service, UnitDeclaration, Variant,
};
use serde::Deserialize;

use crate::error::RepoError;

pub(crate) fn valid_module_id(name: &str) -> bool {
    let mut chars = name.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase())
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ModuleFile {
    module: Header,
    #[serde(default)]
    unit: Vec<UnitTable>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Header {
    name: String,
    about: Option<String>,
}

type Terms = BTreeMap<String, toml::Value>;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct UnitTable {
    id: Option<String>,
    /// A fragment adding to this unit.
    extend: Option<String>,
    /// A fragment replacing the configuration of this unit.
    #[serde(rename = "override")]
    overrides: Option<String>,
    name: Option<String>,
    about: Option<String>,
    parent: Option<String>,
    #[serde(default)]
    always: bool,
    #[serde(default)]
    attended: bool,
    when: Option<Terms>,
    #[serde(default)]
    requires: Vec<String>,
    #[serde(default)]
    after: Vec<String>,
    #[serde(default)]
    packages: Vec<PackageEntry>,
    #[serde(default)]
    aur: Vec<PackageEntry>,
    #[serde(default)]
    services: Vec<ServiceEntry>,
    #[serde(default)]
    files: Vec<FileTable>,
    #[serde(default)]
    variants: Vec<VariantTable>,
    #[serde(default)]
    inputs: Vec<InputTable>,
    #[serde(default)]
    hooks: Vec<HookEntry>,
    choice: Option<ChoiceTable>,
}

/// `choice = { parts = ["zsh", "fish"], default = "zsh" }`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ChoiceTable {
    parts: Vec<String>,
    default: String,
}

#[derive(Deserialize)]
#[serde(untagged, deny_unknown_fields)]
enum PackageEntry {
    Name(String),
    One {
        name: String,
        when: Option<Terms>,
    },
    Several {
        names: Vec<String>,
        when: Option<Terms>,
    },
}

#[derive(Deserialize)]
#[serde(untagged, deny_unknown_fields)]
enum ServiceEntry {
    Name(String),
    Table {
        name: String,
        #[serde(default)]
        now: bool,
        #[serde(default)]
        force: bool,
    },
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "lowercase")]
enum ModeName {
    Symlink,
    #[default]
    Copy,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct FileTable {
    source: String,
    target: String,
    #[serde(default)]
    mode: ModeName,
    #[serde(default)]
    contents: bool,
    #[serde(default)]
    backup: bool,
    permissions: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct VariantTable {
    id: String,
    /// Not needed when a fragment adds options to a variant of the unit.
    name: Option<String>,
    options: Vec<String>,
    default: Option<String>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "lowercase")]
enum KindName {
    #[default]
    Text,
    Bool,
    Secret,
    Choice,
}

#[derive(Deserialize)]
#[serde(untagged, deny_unknown_fields)]
enum OptionEntry {
    Value(String),
    Named { name: String, value: String },
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct InputTable {
    id: String,
    prompt: String,
    #[serde(default)]
    kind: KindName,
    default: Option<toml::Value>,
    #[serde(default)]
    required: bool,
    #[serde(default)]
    options: Vec<OptionEntry>,
    #[serde(default)]
    custom: bool,
}

#[derive(Deserialize)]
#[serde(untagged, deny_unknown_fields)]
enum HookEntry {
    Name(String),
    Table { run: String, when: Option<Terms> },
}

/// Reads a manifest into the declaration of its module.
pub(crate) fn parse(
    path: &Path,
    root: &Path,
    module_id: &str,
    text: &str,
) -> Result<ModuleDeclaration, RepoError> {
    let file: ModuleFile = toml::from_str(text).map_err(|source| RepoError::Toml {
        path: path.to_path_buf(),
        source,
    })?;
    let mut units = Vec::new();
    let mut fragments = Vec::new();
    for table in file.unit {
        match convert_table(path, table)? {
            Converted::Unit(unit) => units.push(unit),
            Converted::Fragment(fragment) => fragments.push(fragment),
        }
    }
    Ok(ModuleDeclaration {
        root: root.to_path_buf(),
        id: module_id.to_string(),
        name: file.module.name,
        about: file.module.about,
        units,
        fragments,
    })
}

/// What a `[[unit]]` table is.
enum Converted {
    Unit(UnitDeclaration),
    Fragment(Fragment),
}

/// The parts a unit and a fragment share.
struct Parts {
    packages: Vec<Package>,
    aur: Vec<Package>,
    services: Vec<Service>,
    files: Vec<FileEntry>,
    variants: Vec<Variant>,
    inputs: Vec<Input>,
    hooks: Vec<Hook>,
}

fn convert_table(path: &Path, table: UnitTable) -> Result<Converted, RepoError> {
    let UnitTable {
        id,
        extend,
        overrides,
        name,
        about,
        parent,
        always,
        attended,
        when,
        requires,
        after,
        packages,
        aur,
        services,
        files,
        variants,
        inputs,
        hooks,
        choice,
    } = table;
    let (label, merge) = match (id, extend, overrides) {
        (Some(id), None, None) => (id, None),
        (None, Some(unit), None) => (unit, Some(Merge::Extend)),
        (None, None, Some(unit)) => (unit, Some(Merge::Override)),
        _ => {
            return Err(RepoError::FragmentKeys {
                path: path.to_path_buf(),
            });
        }
    };
    let when = when
        .map(|t| convert_condition(path, &label, t))
        .transpose()?;
    let parts = convert_parts(
        path,
        &label,
        (packages, aur, services, files, variants, inputs, hooks),
    )?;
    let Some(merge) = merge else {
        let name = name.ok_or_else(|| RepoError::MissingName {
            path: path.to_path_buf(),
            unit: label.clone(),
        })?;
        return Ok(Converted::Unit(UnitDeclaration {
            id: label,
            name,
            about,
            parent,
            always,
            attended,
            when,
            requires,
            after,
            packages: parts.packages,
            aur: parts.aur,
            services: parts.services,
            files: parts.files,
            variants: parts.variants,
            inputs: parts.inputs,
            hooks: parts.hooks,
            choice: choice.map(|c| Choice {
                parts: c.parts,
                default: c.default,
            }),
        }));
    };
    let set = [
        (name.is_some(), "name"),
        (about.is_some(), "about"),
        (parent.is_some(), "parent"),
        (always, "always"),
        (attended, "attended"),
        (!requires.is_empty(), "requires"),
        (!after.is_empty(), "after"),
        (choice.is_some(), "choice"),
    ];
    if let Some((_, field)) = set.iter().find(|(set, _)| *set) {
        return Err(RepoError::FragmentField {
            path: path.to_path_buf(),
            unit: label,
            field,
        });
    }
    Ok(Converted::Fragment(Fragment {
        unit: label,
        merge,
        when,
        packages: parts.packages,
        aur: parts.aur,
        services: parts.services,
        files: parts.files,
        variants: parts.variants,
        inputs: parts.inputs,
        hooks: parts.hooks,
    }))
}

type PartTables = (
    Vec<PackageEntry>,
    Vec<PackageEntry>,
    Vec<ServiceEntry>,
    Vec<FileTable>,
    Vec<VariantTable>,
    Vec<InputTable>,
    Vec<HookEntry>,
);

fn convert_parts(path: &Path, id: &str, tables: PartTables) -> Result<Parts, RepoError> {
    let (packages, aur, services, files, variants, inputs, hooks) = tables;
    let condition = |terms: Option<Terms>| -> Result<Option<Condition>, RepoError> {
        terms.map(|t| convert_condition(path, id, t)).transpose()
    };
    let convert_packages = |entries: Vec<PackageEntry>| -> Result<Vec<Package>, RepoError> {
        let mut out = Vec::new();
        for entry in entries {
            match entry {
                PackageEntry::Name(name) => out.push(Package { name, when: None }),
                PackageEntry::One { name, when } => out.push(Package {
                    name,
                    when: condition(when)?,
                }),
                PackageEntry::Several { names, when } => {
                    let when = condition(when)?;
                    out.extend(names.into_iter().map(|name| Package {
                        name,
                        when: when.clone(),
                    }));
                }
            }
        }
        Ok(out)
    };
    let packages = convert_packages(packages)?;
    let aur = convert_packages(aur)?;
    let mut converted_hooks = Vec::new();
    for hook in hooks {
        converted_hooks.push(match hook {
            HookEntry::Name(run) => Hook { run, when: None },
            HookEntry::Table { run, when } => Hook {
                run,
                when: condition(when)?,
            },
        });
    }
    let mut converted_files = Vec::new();
    for f in files {
        let permissions = match f.permissions {
            None => None,
            Some(text) => Some(
                u32::from_str_radix(&text, 8)
                    .ok()
                    .filter(|_| !text.is_empty())
                    .ok_or_else(|| RepoError::Permissions {
                        path: path.to_path_buf(),
                        unit: id.to_string(),
                        value: text.clone(),
                    })?,
            ),
        };
        converted_files.push(FileEntry {
            source: f.source,
            target: f.target,
            mode: match f.mode {
                ModeName::Symlink => Mode::Symlink,
                ModeName::Copy => Mode::Copy,
            },
            contents: f.contents,
            backup: f.backup,
            permissions,
        });
    }
    let mut converted_inputs = Vec::new();
    for input in inputs {
        let default = match input.default {
            None => None,
            Some(toml::Value::String(text)) => Some(text),
            Some(toml::Value::Boolean(flag)) => Some(flag.to_string()),
            Some(_) => {
                return Err(RepoError::InputDefault {
                    path: path.to_path_buf(),
                    unit: id.to_string(),
                    input: input.id,
                });
            }
        };
        converted_inputs.push(Input {
            id: input.id,
            prompt: input.prompt,
            kind: match input.kind {
                KindName::Text => InputKind::Text,
                KindName::Bool => InputKind::Bool,
                KindName::Secret => InputKind::Secret,
                KindName::Choice => InputKind::Choice,
            },
            default,
            required: input.required,
            options: input
                .options
                .into_iter()
                .map(|o| match o {
                    OptionEntry::Value(value) => InputOption {
                        name: value.clone(),
                        value,
                    },
                    OptionEntry::Named { name, value } => InputOption { name, value },
                })
                .collect(),
            custom: input.custom,
        });
    }
    Ok(Parts {
        packages,
        aur,
        services: services
            .into_iter()
            .map(|s| match s {
                ServiceEntry::Name(name) => Service {
                    name,
                    now: false,
                    force: false,
                },
                ServiceEntry::Table { name, now, force } => Service { name, now, force },
            })
            .collect(),
        files: converted_files,
        variants: variants
            .into_iter()
            .map(|v| Variant {
                id: v.id,
                name: v.name.unwrap_or_default(),
                options: v.options,
                default: v.default,
            })
            .collect(),
        inputs: converted_inputs,
        hooks: converted_hooks,
    })
}

/// `when = { arch = "x86_64", vm = false, gpu = ["nvidia", "amd"] }`.
fn convert_condition(path: &Path, unit: &str, terms: Terms) -> Result<Condition, RepoError> {
    let mut converted = Vec::new();
    for (fact, value) in terms {
        let expected = match value {
            toml::Value::Boolean(flag) => Expected::Flag(flag),
            toml::Value::String(word) => Expected::Words(vec![word]),
            toml::Value::Array(items) => {
                let words: Option<Vec<String>> = items
                    .into_iter()
                    .map(|item| item.as_str().map(str::to_string))
                    .collect();
                match words {
                    Some(words) if !words.is_empty() => Expected::Words(words),
                    _ => {
                        return Err(RepoError::ConditionValue {
                            path: path.to_path_buf(),
                            unit: unit.into(),
                            fact,
                        });
                    }
                }
            }
            _ => {
                return Err(RepoError::ConditionValue {
                    path: path.to_path_buf(),
                    unit: unit.into(),
                    fact,
                });
            }
        };
        converted.push((fact, expected));
    }
    Condition::new(converted).map_err(|source| RepoError::Condition {
        path: path.to_path_buf(),
        unit: unit.into(),
        source,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn parse_text(text: &str) -> Result<ModuleDeclaration, RepoError> {
        parse(
            &PathBuf::from("modules/demo.toml"),
            &PathBuf::from("/repo"),
            "demo",
            text,
        )
    }

    #[test]
    fn a_manifest_converts_with_its_defaults() {
        let module = parse_text(
            r#"
[module]
name = "Demo"

[[unit]]
id = "nvidia"
name = "NVIDIA"
when = { gpu = "nvidia", vm = false }
packages = ["nvidia-utils", { name = "lib32-nvidia-utils", when = { arch = "x86_64" } },
            { names = ["a", "b"], when = { distro = ["arch", "ubuntu"] } }]
services = ["bluetooth", { name = "sddm", force = true }]
files = [{ source = ".config/x/{theme}", target = ".config/x" },
         { source = "bin", target = ".local/bin", contents = true, backup = true, permissions = "755" },
         { source = "lnk", target = ".lnk", mode = "symlink" },
         { source = "nas.cred", target = "/etc/samba/nas.cred", mode = "copy", permissions = "600" }]
variants = [{ id = "theme", name = "Theme", options = ["a", "b"], default = "b" }]
inputs = [{ id = "fido", prompt = "FIDO?", kind = "bool", default = false },
          { id = "repo", prompt = "Repo", kind = "choice", custom = true, options = ["x", { name = "Y", value = "y" }] }]
hooks = ["setup", { run = "build", when = { arch = "aarch64" } }]
"#,
        )
        .unwrap();
        assert_eq!(module.name, "Demo");
        let unit = &module.units[0];
        assert_eq!(unit.id, "nvidia");
        assert!(unit.when.is_some());
        assert_eq!(unit.packages.len(), 4);
        assert_eq!(
            unit.packages[0],
            Package {
                name: "nvidia-utils".into(),
                when: None
            }
        );
        assert!(unit.packages[1].when.is_some());
        assert_eq!(unit.packages[2].name, "a");
        assert_eq!(unit.packages[2].when, unit.packages[3].when);
        assert_eq!(
            unit.services[0],
            Service {
                name: "bluetooth".into(),
                now: false,
                force: false
            }
        );
        assert!(unit.services[1].force);
        assert_eq!(unit.files[0].mode, Mode::Copy, "a copy by default");
        assert!(!unit.files[0].backup, "no backup by default");
        assert_eq!(unit.files[1].mode, Mode::Copy);
        assert!(unit.files[1].contents && unit.files[1].backup);
        assert_eq!(unit.files[1].permissions, Some(0o755));
        assert_eq!(unit.files[2].mode, Mode::Symlink);
        assert!(unit.files[3].is_system());
        assert_eq!(unit.files[3].permissions, Some(0o600));
        assert_eq!(module.root, PathBuf::from("/repo"));
        assert_eq!(unit.variants[0].default.as_deref(), Some("b"));
        assert_eq!(unit.inputs[0].kind, InputKind::Bool);
        assert_eq!(unit.inputs[0].default.as_deref(), Some("false"));
        assert_eq!(
            unit.inputs[1].options[0],
            InputOption {
                name: "x".into(),
                value: "x".into()
            }
        );
        assert_eq!(
            unit.inputs[1].options[1],
            InputOption {
                name: "Y".into(),
                value: "y".into()
            }
        );
        assert!(unit.inputs[1].custom);
        assert_eq!(
            unit.hooks[0],
            Hook {
                run: "setup".into(),
                when: None
            }
        );
        assert!(unit.hooks[1].when.is_some());
    }

    #[test]
    fn mistakes_are_reported_with_the_file() {
        let unknown = parse_text(
            "[module]\nname = \"Demo\"\n\n[[unit]]\nid = \"x\"\nname = \"X\"\ncolour = \"blue\"\n",
        )
        .unwrap_err();
        assert!(matches!(unknown, RepoError::Toml { .. }), "{unknown}");
        assert!(
            unknown.to_string().contains("modules/demo.toml"),
            "{unknown}"
        );

        let bad_fact = parse_text("[module]\nname = \"Demo\"\n\n[[unit]]\nid = \"x\"\nname = \"X\"\nwhen = { colour = \"blue\" }\n").unwrap_err();
        assert!(
            matches!(bad_fact, RepoError::Condition { .. }),
            "{bad_fact}"
        );
        assert!(
            bad_fact.to_string().contains("unknown property colour"),
            "{bad_fact}"
        );

        let bad_value = parse_text(
            "[module]\nname = \"Demo\"\n\n[[unit]]\nid = \"x\"\nname = \"X\"\nwhen = { vm = 3 }\n",
        )
        .unwrap_err();
        assert!(
            matches!(bad_value, RepoError::ConditionValue { .. }),
            "{bad_value}"
        );

        let bad_permissions = parse_text("[module]\nname = \"Demo\"\n\n[[unit]]\nid = \"x\"\nname = \"X\"\nfiles = [{ source = \"a\", target = \"b\", mode = \"copy\", permissions = \"rwx\" }]\n").unwrap_err();
        assert!(
            matches!(bad_permissions, RepoError::Permissions { .. }),
            "{bad_permissions}"
        );

        let bad_default = parse_text("[module]\nname = \"Demo\"\n\n[[unit]]\nid = \"x\"\nname = \"X\"\ninputs = [{ id = \"n\", prompt = \"N\", default = 3 }]\n").unwrap_err();
        assert!(
            matches!(bad_default, RepoError::InputDefault { .. }),
            "{bad_default}"
        );
    }

    #[test]
    fn fragments_extend_or_override_a_unit_and_set_nothing_else() {
        let module = parse_text(
            r#"
[module]
name = "Work"

[[unit]]
extend = "desktop"
when = { gpu = "nvidia" }
files = [{ source = "files/local.lua", target = ".config/hypr/local.lua" }]
variants = [{ id = "work", name = "Work", options = ["a"] }]
hooks = ["announce"]

[[unit]]
override = "shell"
files = [{ source = "files/zshrc", target = ".zshrc" }]
"#,
        )
        .unwrap();
        assert!(module.units.is_empty());
        assert_eq!(module.fragments.len(), 2);
        let extend = &module.fragments[0];
        assert_eq!(
            (extend.unit.as_str(), extend.merge),
            ("desktop", Merge::Extend)
        );
        assert!(extend.when.is_some());
        assert_eq!(extend.files[0].target, ".config/hypr/local.lua");
        assert_eq!(extend.hooks[0].run, "announce");
        assert_eq!(module.fragments[1].merge, Merge::Override);

        let shell = parse_text(
            "[module]\nname = \"T\"\n\n[[unit]]\nid = \"shell\"\nname = \"Shell\"\npackages = [\"starship\"]\nchoice = { parts = [\"zsh\", \"fish\"], default = \"zsh\" }\n",
        )
        .unwrap();
        let choice = shell.units[0].choice.as_ref().unwrap();
        assert_eq!(choice.parts, ["zsh", "fish"]);
        assert_eq!(choice.default, "zsh");
        let chooser = parse_text(
            "[module]\nname = \"T\"\n\n[[unit]]\nextend = \"shell\"\nchoice = { parts = [\"a\", \"b\"], default = \"a\" }\n",
        );
        assert!(matches!(
            chooser.unwrap_err(),
            RepoError::FragmentField {
                field: "choice",
                ..
            }
        ));

        let both = parse_text(
            "[module]\nname = \"W\"\n\n[[unit]]\nid = \"x\"\nextend = \"y\"\nname = \"X\"\n",
        );
        assert!(matches!(both.unwrap_err(), RepoError::FragmentKeys { .. }));
        let named =
            parse_text("[module]\nname = \"W\"\n\n[[unit]]\nextend = \"y\"\nname = \"X\"\n");
        assert!(matches!(
            named.unwrap_err(),
            RepoError::FragmentField { field: "name", .. }
        ));
        let nameless =
            parse_text("[module]\nname = \"W\"\n\n[[unit]]\nid = \"x\"\npackages = [\"p\"]\n");
        assert!(matches!(
            nameless.unwrap_err(),
            RepoError::MissingName { .. }
        ));
    }
}
