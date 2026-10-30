//! The validated declarations of a repository, for one machine: which units
//! exist, which apply to it (available), which are picked by hand (offered).

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use thiserror::Error;

use crate::declarations::{
    Choice, Declarations, FileEntry, Fragment, Input, InputKind, Merge, Mode, ModuleDeclaration,
    Service, UnitDeclaration, Variant,
};
use crate::platform::Platform;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum RegistryError {
    #[error("module {0}: declared twice")]
    DuplicateModule(String),
    #[error("module {0}: the name is missing or spans several lines")]
    ModuleName(String),
    #[error(
        "unit {0}: the id must be lower-case letters, digits and dashes, starting with a letter"
    )]
    BadUnitId(String),
    #[error("unit {id}: declared in {module} and in {other}")]
    DuplicateUnit {
        id: String,
        module: String,
        other: String,
    },
    #[error("unit {0}: the name is missing or spans several lines")]
    UnitName(String),
    #[error("unit {unit}: unknown parent {parent}")]
    UnknownParent { unit: String, parent: String },
    #[error("unit {unit}: its parent {parent} is in a module read after")]
    ParentInLaterModule { unit: String, parent: String },
    #[error("unit {0}: is its own parent")]
    SelfParent(String),
    #[error("unit {unit}: its parent {parent} is itself a part")]
    NestedPart { unit: String, parent: String },
    #[error("unit {unit}: {relation} names an unknown unit {target}")]
    UnknownReference {
        unit: String,
        relation: &'static str,
        target: String,
    },
    #[error("unit {unit}: {relation} names the unit itself")]
    SelfReference {
        unit: String,
        relation: &'static str,
    },
    #[error("unit {unit}: {list} has an empty name")]
    EmptyName { unit: String, list: &'static str },
    #[error("unit {unit}: {list} repeats {name}")]
    Repeated {
        unit: String,
        list: &'static str,
        name: String,
    },
    #[error(
        "unit {unit}: the variant id {variant} must be lower-case letters, digits and underscores"
    )]
    BadVariantId { unit: String, variant: String },
    #[error("unit {unit}: variant {variant} has no option")]
    VariantWithoutOptions { unit: String, variant: String },
    #[error(
        "unit {unit}: variant {variant} has {option} as default, which is not one of its options"
    )]
    VariantDefault {
        unit: String,
        variant: String,
        option: String,
    },
    #[error("unit {unit}: variant {variant} is used by no file")]
    UnusedVariant { unit: String, variant: String },
    #[error("unit {unit}: the source {path} names {placeholder}, which is no variant of the unit")]
    UnknownPlaceholder {
        unit: String,
        path: String,
        placeholder: String,
    },
    #[error("unit {unit}: the target {target} must not be empty nor hold ..")]
    BadTarget { unit: String, target: String },
    #[error("unit {unit}: {target} is a system file: it is copied, with permissions")]
    SystemFile { unit: String, target: String },
    #[error("unit {unit}: {target} is a link, which has no permissions of its own")]
    PermissionsOnLink { unit: String, target: String },
    #[error("unit {unit}: the input id {input} must be lower-case letters, digits and underscores")]
    BadInputId { unit: String, input: String },
    #[error("unit {unit}: input {input} has no prompt")]
    InputPrompt { unit: String, input: String },
    #[error("unit {unit}: input {input} has no option")]
    InputWithoutOptions { unit: String, input: String },
    #[error("unit {unit}: input {input} has {value} as default, which is not one of its options")]
    InputDefault {
        unit: String,
        input: String,
        value: String,
    },
    #[error("unit {unit}: input {input} is not a choice: no options, no custom")]
    NotAChoice { unit: String, input: String },
    #[error("unit {unit}: input {input} is not a text: it cannot be required")]
    NotAText { unit: String, input: String },
    #[error("unit {unit}: input {input} has {value} as default, which is not true or false")]
    InputFlag {
        unit: String,
        input: String,
        value: String,
    },
    #[error("unit {0}: declares nothing to do")]
    NothingToDo(String),
    #[error("unit {0}: attended, but without hooks")]
    AttendedWithoutHooks(String),
    #[error("the units require or follow each other in a cycle: {}", .0.join(" -> "))]
    Cycle(Vec<String>),
    #[error("module {module}: extends or overrides {unit}, which no module read before declares")]
    UnknownExtended { module: String, unit: String },
    #[error("module {module}: extends or overrides its own unit {unit}")]
    ExtendedOwnModule { module: String, unit: String },
    #[error("unit {unit}: overridden by {module} and by {other}")]
    OverriddenTwice {
        unit: String,
        module: String,
        other: String,
    },
    #[error("unit {unit}: variant {variant} has no name")]
    VariantName { unit: String, variant: String },
    #[error("unit {unit}: a choice is between at least two parts")]
    ChoiceTooSmall { unit: String },
    #[error("unit {unit}: the choice names {part}, which is not one of its parts")]
    ChoiceNotAPart { unit: String, part: String },
    #[error("unit {unit}: the default {default} of the choice is not one of its parts")]
    ChoiceDefault { unit: String, default: String },
    #[error("unit {unit}: requires {part}, one of the parts of its choice")]
    ChoiceRequired { unit: String, part: String },
    #[error("module {module}: adds parts to the choice of {unit}, which has none")]
    NoChoice { module: String, unit: String },
    #[error("unit {unit}: the choice {module} gives it has no default")]
    ChoiceWithoutDefault { unit: String, module: String },
}

/// A hook of a unit: the function, and the folder of the module whose
/// `hooks.sh` defines it (a fragment's module for the hooks it brings).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HookRun {
    pub function: String,
    pub module_root: PathBuf,
}

/// A unit declaration with the fragments of later modules applied.
struct Merged {
    decl: UnitDeclaration,
    /// The module folder of each hook of `decl.hooks`.
    hook_roots: Vec<PathBuf>,
    /// (variant, option) -> the module folder holding the files of an
    /// option a fragment added.
    option_roots: BTreeMap<(String, String), PathBuf>,
    /// The modules whose fragments applied, in order.
    extended_by: Vec<String>,
}

impl Merged {
    fn new(decl: &UnitDeclaration, root: &Path) -> Merged {
        Merged {
            decl: decl.clone(),
            hook_roots: vec![root.to_path_buf(); decl.hooks.len()],
            option_roots: BTreeMap::new(),
            extended_by: Vec::new(),
        }
    }

    /// Applies a fragment of `module`. Its file sources become absolute,
    /// its hooks remember their module, and so do the options it adds to
    /// the unit's variants. Its parts join the choice of the unit, or
    /// replace it.
    fn apply(
        &mut self,
        fragment: &Fragment,
        module: &ModuleDeclaration,
    ) -> Result<(), RegistryError> {
        let root = &module.root;
        let absolute = |file: &FileEntry| FileEntry {
            source: root.join(&file.source).to_string_lossy().into_owned(),
            ..file.clone()
        };
        self.decl.packages.extend(fragment.packages.iter().cloned());
        self.decl.aur.extend(fragment.aur.iter().cloned());
        self.decl.services.extend(fragment.services.iter().cloned());
        match fragment.merge {
            Merge::Extend => {
                for file in &fragment.files {
                    self.decl.files.retain(|f| f.target != file.target);
                    self.decl.files.push(absolute(file));
                }
                // The variants no file names any more leave with the files
                // they served
                let used: BTreeSet<String> = self
                    .decl
                    .files
                    .iter()
                    .flat_map(|f| placeholders(&f.source))
                    .collect();
                self.decl.variants.retain(|v| used.contains(&v.id));
                for variant in &fragment.variants {
                    let Some(existing) = self.decl.variants.iter_mut().find(|v| v.id == variant.id)
                    else {
                        self.decl.variants.push(variant.clone());
                        continue;
                    };
                    // More options for a variant of the unit, their files in
                    // the fragment's module
                    for option in &variant.options {
                        if existing.options.contains(option) {
                            return Err(RegistryError::Repeated {
                                unit: self.decl.id.clone(),
                                list: "variant options",
                                name: format!("{}: {option}", variant.id),
                            });
                        }
                        existing.options.push(option.clone());
                        self.option_roots
                            .insert((variant.id.clone(), option.clone()), root.clone());
                    }
                    if variant.default.is_some() {
                        existing.default = variant.default.clone();
                    }
                }
                self.decl.inputs.extend(fragment.inputs.iter().cloned());
                self.decl.hooks.extend(fragment.hooks.iter().cloned());
                self.hook_roots
                    .extend(std::iter::repeat_n(root.clone(), fragment.hooks.len()));
                if let Some(change) = &fragment.choice {
                    let Some(choice) = &mut self.decl.choice else {
                        return Err(RegistryError::NoChoice {
                            module: module.id.clone(),
                            unit: self.decl.id.clone(),
                        });
                    };
                    for part in &change.parts {
                        if choice.parts.contains(part) {
                            return Err(RegistryError::Repeated {
                                unit: self.decl.id.clone(),
                                list: "choice parts",
                                name: part.clone(),
                            });
                        }
                        choice.parts.push(part.clone());
                    }
                    if let Some(default) = &change.default {
                        choice.default = default.clone();
                    }
                }
            }
            Merge::Override => {
                self.decl.files = fragment.files.iter().map(absolute).collect();
                self.decl.variants = fragment.variants.clone();
                self.decl.inputs = fragment.inputs.clone();
                self.decl.hooks = fragment.hooks.clone();
                self.hook_roots = vec![root.clone(); fragment.hooks.len()];
                self.option_roots.clear();
                // The choice stays unless the fragment gives another: its
                // parts are units, not configuration
                if let Some(change) = &fragment.choice {
                    let Some(default) = &change.default else {
                        return Err(RegistryError::ChoiceWithoutDefault {
                            unit: self.decl.id.clone(),
                            module: module.id.clone(),
                        });
                    };
                    self.decl.choice = Some(Choice {
                        parts: change.parts.clone(),
                        default: default.clone(),
                    });
                }
            }
        }
        self.extended_by.push(module.id.clone());
        Ok(())
    }
}

/// A module: a heading, and its units in declaration order.
#[derive(Debug, Clone)]
pub struct Module {
    id: String,
    name: String,
    about: Option<String>,
    root: PathBuf,
    units: Vec<Unit>,
}

impl Module {
    pub fn id(&self) -> &str {
        &self.id
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn about(&self) -> Option<&str> {
        self.about.as_deref()
    }

    /// The folder of the module: its files and its hook script are there.
    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn units(&self) -> &[Unit] {
        &self.units
    }
}

/// A unit of a module, as it stands on this machine.
#[derive(Debug, Clone)]
pub struct Unit {
    decl: UnitDeclaration,
    module: String,
    root: PathBuf,
    available: bool,
    offered: bool,
    packages: Vec<String>,
    aur: Vec<String>,
    hooks: Vec<HookRun>,
    option_roots: BTreeMap<(String, String), PathBuf>,
    extended_by: Vec<String>,
}

impl Unit {
    pub fn id(&self) -> &str {
        &self.decl.id
    }

    pub fn name(&self) -> &str {
        &self.decl.name
    }

    pub fn about(&self) -> Option<&str> {
        self.decl.about.as_deref()
    }

    /// The module declaring it.
    pub fn module(&self) -> &str {
        &self.module
    }

    /// The folder of its module: the sources of its files and its hook
    /// script are there.
    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn parent(&self) -> Option<&str> {
        self.decl.parent.as_deref()
    }

    pub fn always(&self) -> bool {
        self.decl.always
    }

    pub fn attended(&self) -> bool {
        self.decl.attended
    }

    pub fn requires(&self) -> &[String] {
        &self.decl.requires
    }

    pub fn after(&self) -> &[String] {
        &self.decl.after
    }

    /// Applies to this machine.
    pub fn available(&self) -> bool {
        self.available
    }

    /// Picked by hand: available, not always run, not a part its parent
    /// requires.
    pub fn offered(&self) -> bool {
        self.offered
    }

    /// The packages for this machine.
    pub fn packages(&self) -> &[String] {
        &self.packages
    }

    /// The AUR packages for this machine.
    pub fn aur(&self) -> &[String] {
        &self.aur
    }

    pub fn services(&self) -> &[Service] {
        &self.decl.services
    }

    pub fn files(&self) -> &[FileEntry] {
        &self.decl.files
    }

    pub fn variants(&self) -> &[Variant] {
        &self.decl.variants
    }

    pub fn variant(&self, id: &str) -> Option<&Variant> {
        self.decl.variants.iter().find(|v| v.id == id)
    }

    pub fn inputs(&self) -> &[Input] {
        &self.decl.inputs
    }

    pub fn input(&self, id: &str) -> Option<&Input> {
        self.decl.inputs.iter().find(|i| i.id == id)
    }

    /// The hooks for this machine, in order: their functions.
    pub fn hooks(&self) -> impl Iterator<Item = &str> {
        self.hooks.iter().map(|h| h.function.as_str())
    }

    /// The hooks for this machine, each with the module defining it.
    pub fn hook_runs(&self) -> &[HookRun] {
        &self.hooks
    }

    /// The modules whose fragments changed the unit, in order.
    pub fn extended_by(&self) -> &[String] {
        &self.extended_by
    }

    /// The exclusive parts of the unit, when it has some.
    pub fn choice(&self) -> Option<&Choice> {
        self.decl.choice.as_ref()
    }

    /// The module folder holding the files of an option a fragment added to
    /// a variant; none for the unit's own options.
    pub fn option_root(&self, variant: &str, option: &str) -> Option<&Path> {
        self.option_roots
            .get(&(variant.to_string(), option.to_string()))
            .map(PathBuf::as_path)
    }

    /// As declared, conditions included.
    pub fn declaration(&self) -> &UnitDeclaration {
        &self.decl
    }
}

/// The modules and units of a repository, validated for one machine.
#[derive(Debug, Clone)]
pub struct Registry {
    modules: Vec<Module>,
    /// unit id -> (module index, unit index)
    index: BTreeMap<String, (usize, usize)>,
}

fn valid_id(id: &str, extra: char) -> bool {
    let mut chars = id.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase())
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == extra)
}

fn one_line(text: &str) -> bool {
    !text.trim().is_empty() && !text.contains('\n')
}

impl Registry {
    /// Validates the declarations and computes what applies to the machine.
    pub fn new(declarations: Declarations, platform: &Platform) -> Result<Registry, RegistryError> {
        let mut merged: Vec<Vec<Merged>> = Vec::new();
        let mut index = BTreeMap::new();
        for (m, module) in declarations.modules.iter().enumerate() {
            if !one_line(&module.name) {
                return Err(RegistryError::ModuleName(module.id.clone()));
            }
            if declarations.modules[..m]
                .iter()
                .any(|other| other.id == module.id)
            {
                return Err(RegistryError::DuplicateModule(module.id.clone()));
            }
            let mut units = Vec::new();
            for (u, decl) in module.units.iter().enumerate() {
                if !valid_id(&decl.id, '-') {
                    return Err(RegistryError::BadUnitId(decl.id.clone()));
                }
                if let Some(&(other, _)) = index.get(&decl.id) {
                    let other: &ModuleDeclaration = &declarations.modules[other];
                    return Err(RegistryError::DuplicateUnit {
                        id: decl.id.clone(),
                        module: module.id.clone(),
                        other: other.id.clone(),
                    });
                }
                index.insert(decl.id.clone(), (m, u));
                units.push(Merged::new(decl, &module.root));
            }
            merged.push(units);
        }
        // The fragments, in module order, each onto a unit of a module read
        // before
        let mut overridden: BTreeMap<String, String> = BTreeMap::new();
        for (m, module) in declarations.modules.iter().enumerate() {
            for fragment in &module.fragments {
                let Some(&(target_m, target_u)) = index.get(&fragment.unit) else {
                    return Err(RegistryError::UnknownExtended {
                        module: module.id.clone(),
                        unit: fragment.unit.clone(),
                    });
                };
                if target_m == m {
                    return Err(RegistryError::ExtendedOwnModule {
                        module: module.id.clone(),
                        unit: fragment.unit.clone(),
                    });
                }
                if target_m > m {
                    return Err(RegistryError::UnknownExtended {
                        module: module.id.clone(),
                        unit: fragment.unit.clone(),
                    });
                }
                if fragment.merge == Merge::Override {
                    if let Some(other) = overridden.insert(fragment.unit.clone(), module.id.clone())
                    {
                        return Err(RegistryError::OverriddenTwice {
                            unit: fragment.unit.clone(),
                            module: module.id.clone(),
                            other,
                        });
                    }
                }
                if fragment.when.as_ref().is_none_or(|c| c.holds(platform)) {
                    merged[target_m][target_u].apply(fragment, module)?;
                }
            }
        }
        let mut modules = Vec::new();
        for (module, merged) in declarations.modules.iter().zip(&merged) {
            let units = merged
                .iter()
                .map(|unit| Unit::new(unit, module, platform))
                .collect::<Result<Vec<Unit>, RegistryError>>()?;
            modules.push(Module {
                id: module.id.clone(),
                name: module.name.clone(),
                about: module.about.clone(),
                root: module.root.clone(),
                units,
            });
        }
        let registry = Registry { modules, index };
        registry.check_references()?;
        registry.check_cycles()?;
        Ok(registry.with_offers())
    }

    /// The units a part is hidden behind: references, parents.
    fn check_references(&self) -> Result<(), RegistryError> {
        for unit in self.units() {
            if let Some(parent) = unit.parent() {
                let Some(parent_unit) = self.unit(parent) else {
                    return Err(RegistryError::UnknownParent {
                        unit: unit.id().into(),
                        parent: parent.into(),
                    });
                };
                if parent == unit.id() {
                    return Err(RegistryError::SelfParent(unit.id().into()));
                }
                // The parent is in the same module, or in one read before:
                // a private part under a public unit
                if self.index[parent].0 > self.index[unit.id()].0 {
                    return Err(RegistryError::ParentInLaterModule {
                        unit: unit.id().into(),
                        parent: parent.into(),
                    });
                }
                if parent_unit.parent().is_some() {
                    return Err(RegistryError::NestedPart {
                        unit: unit.id().into(),
                        parent: parent.into(),
                    });
                }
            }
            if let Some(choice) = unit.choice() {
                if choice.parts.len() < 2 {
                    return Err(RegistryError::ChoiceTooSmall {
                        unit: unit.id().into(),
                    });
                }
                for part in &choice.parts {
                    if !self
                        .unit(part)
                        .is_some_and(|p| p.parent() == Some(unit.id()))
                    {
                        return Err(RegistryError::ChoiceNotAPart {
                            unit: unit.id().into(),
                            part: part.clone(),
                        });
                    }
                    if unit.requires().contains(part) {
                        return Err(RegistryError::ChoiceRequired {
                            unit: unit.id().into(),
                            part: part.clone(),
                        });
                    }
                }
                if !choice.parts.contains(&choice.default) {
                    return Err(RegistryError::ChoiceDefault {
                        unit: unit.id().into(),
                        default: choice.default.clone(),
                    });
                }
            }
            for (relation, targets) in [("requires", unit.requires()), ("after", unit.after())] {
                for target in targets {
                    if target == unit.id() {
                        return Err(RegistryError::SelfReference {
                            unit: unit.id().into(),
                            relation,
                        });
                    }
                    if self.unit(target).is_none() {
                        return Err(RegistryError::UnknownReference {
                            unit: unit.id().into(),
                            relation,
                            target: target.clone(),
                        });
                    }
                }
            }
        }
        Ok(())
    }

    /// No cycle through requires and after.
    fn check_cycles(&self) -> Result<(), RegistryError> {
        fn visit<'a>(
            reg: &'a Registry,
            id: &'a str,
            done: &mut BTreeSet<&'a str>,
            stack: &mut Vec<&'a str>,
        ) -> Result<(), RegistryError> {
            if done.contains(id) {
                return Ok(());
            }
            if let Some(position) = stack.iter().position(|s| *s == id) {
                let mut cycle: Vec<String> =
                    stack[position..].iter().map(|s| s.to_string()).collect();
                cycle.push(id.to_string());
                return Err(RegistryError::Cycle(cycle));
            }
            stack.push(id);
            let unit = reg.unit(id).expect("references are checked first");
            for next in unit.requires().iter().chain(unit.after()) {
                visit(reg, next, done, stack)?;
            }
            stack.pop();
            done.insert(id);
            Ok(())
        }
        let mut done = BTreeSet::new();
        for unit in self.units() {
            visit(self, unit.id(), &mut done, &mut Vec::new())?;
        }
        Ok(())
    }

    /// Marks the offered units: available, not always run, and not a part
    /// its parent requires.
    fn with_offers(mut self) -> Registry {
        let required_parts: BTreeSet<String> = self
            .units()
            .flat_map(|u| u.requires().to_vec())
            .filter(|target| self.unit(target).and_then(Unit::parent).is_some())
            .collect();
        for module in &mut self.modules {
            for unit in &mut module.units {
                unit.offered =
                    unit.available && !unit.decl.always && !required_parts.contains(&unit.decl.id);
            }
        }
        self
    }

    pub fn modules(&self) -> &[Module] {
        &self.modules
    }

    /// Every unit, modules and declarations in order.
    pub fn units(&self) -> impl Iterator<Item = &Unit> {
        self.modules.iter().flat_map(|m| m.units.iter())
    }

    pub fn unit(&self, id: &str) -> Option<&Unit> {
        self.index.get(id).map(|&(m, u)| &self.modules[m].units[u])
    }

    /// The position of a unit in the declaration order.
    pub fn position(&self, id: &str) -> Option<usize> {
        self.units().position(|u| u.id() == id)
    }

    /// The parts of a unit, in order.
    pub fn parts<'a>(&'a self, parent: &'a str) -> impl Iterator<Item = &'a Unit> + 'a {
        self.units().filter(move |u| u.parent() == Some(parent))
    }

    /// The parent whose choice a part belongs to, with that choice.
    pub fn choice_of(&self, part: &str) -> Option<(&Unit, &Choice)> {
        let parent = self.unit(part)?.parent()?;
        let unit = self.unit(parent)?;
        let choice = unit.choice()?;
        choice
            .parts
            .iter()
            .any(|p| p == part)
            .then_some((unit, choice))
    }

    /// The units requiring a unit.
    pub fn required_by<'a>(&'a self, id: &'a str) -> impl Iterator<Item = &'a Unit> + 'a {
        self.units()
            .filter(move |u| u.requires().iter().any(|r| r == id))
    }
}

impl Unit {
    fn new(
        merged: &Merged,
        module: &ModuleDeclaration,
        platform: &Platform,
    ) -> Result<Unit, RegistryError> {
        let decl = &merged.decl;
        let id = &decl.id;
        if !one_line(&decl.name) {
            return Err(RegistryError::UnitName(id.clone()));
        }
        let applicable = |list: &[crate::declarations::Package], name: &'static str| {
            let mut seen = BTreeSet::new();
            let mut out = Vec::new();
            for package in list {
                if package.name.is_empty() {
                    return Err(RegistryError::EmptyName {
                        unit: id.clone(),
                        list: name,
                    });
                }
                if !seen.insert(package.name.as_str()) {
                    return Err(RegistryError::Repeated {
                        unit: id.clone(),
                        list: name,
                        name: package.name.clone(),
                    });
                }
                if package.when.as_ref().is_none_or(|c| c.holds(platform)) {
                    out.push(package.name.clone());
                }
            }
            Ok(out)
        };
        let packages = applicable(&decl.packages, "packages")?;
        let aur = applicable(&decl.aur, "aur")?;

        let mut seen = BTreeSet::new();
        for service in &decl.services {
            if service.name.is_empty() {
                return Err(RegistryError::EmptyName {
                    unit: id.clone(),
                    list: "services",
                });
            }
            if !seen.insert(service.name.as_str()) {
                return Err(RegistryError::Repeated {
                    unit: id.clone(),
                    list: "services",
                    name: service.name.clone(),
                });
            }
        }

        let mut variant_ids = BTreeSet::new();
        for variant in &decl.variants {
            if !valid_id(&variant.id, '_') {
                return Err(RegistryError::BadVariantId {
                    unit: id.clone(),
                    variant: variant.id.clone(),
                });
            }
            if !one_line(&variant.name) {
                return Err(RegistryError::VariantName {
                    unit: id.clone(),
                    variant: variant.id.clone(),
                });
            }
            if !variant_ids.insert(variant.id.as_str()) {
                return Err(RegistryError::Repeated {
                    unit: id.clone(),
                    list: "variants",
                    name: variant.id.clone(),
                });
            }
            if variant.options.is_empty() {
                return Err(RegistryError::VariantWithoutOptions {
                    unit: id.clone(),
                    variant: variant.id.clone(),
                });
            }
            if let Some(default) = &variant.default {
                if !variant.options.contains(default) {
                    return Err(RegistryError::VariantDefault {
                        unit: id.clone(),
                        variant: variant.id.clone(),
                        option: default.clone(),
                    });
                }
            }
        }
        let mut used = BTreeSet::new();
        for file in &decl.files {
            check_target(id, file)?;
            for placeholder in placeholders(&file.source) {
                if !variant_ids.contains(placeholder.as_str()) {
                    return Err(RegistryError::UnknownPlaceholder {
                        unit: id.clone(),
                        path: file.source.clone(),
                        placeholder,
                    });
                }
                used.insert(placeholder);
            }
        }
        if let Some(unused) = variant_ids.iter().find(|v| !used.contains(**v)) {
            return Err(RegistryError::UnusedVariant {
                unit: id.clone(),
                variant: unused.to_string(),
            });
        }

        let mut input_ids = BTreeSet::new();
        for input in &decl.inputs {
            check_input(id, input)?;
            if !input_ids.insert(input.id.as_str()) {
                return Err(RegistryError::Repeated {
                    unit: id.clone(),
                    list: "inputs",
                    name: input.id.clone(),
                });
            }
        }

        let mut seen = BTreeSet::new();
        let mut hooks = Vec::new();
        for (hook, root) in decl.hooks.iter().zip(&merged.hook_roots) {
            if hook.run.is_empty() {
                return Err(RegistryError::EmptyName {
                    unit: id.clone(),
                    list: "hooks",
                });
            }
            if !seen.insert(hook.run.as_str()) {
                return Err(RegistryError::Repeated {
                    unit: id.clone(),
                    list: "hooks",
                    name: hook.run.clone(),
                });
            }
            if hook.when.as_ref().is_none_or(|c| c.holds(platform)) {
                hooks.push(HookRun {
                    function: hook.run.clone(),
                    module_root: root.clone(),
                });
            }
        }

        let declared = !decl.packages.is_empty()
            || !decl.aur.is_empty()
            || !decl.services.is_empty()
            || !decl.files.is_empty()
            || !decl.hooks.is_empty();
        if !declared {
            return Err(RegistryError::NothingToDo(id.clone()));
        }
        if decl.attended && decl.hooks.is_empty() {
            return Err(RegistryError::AttendedWithoutHooks(id.clone()));
        }

        let available = decl.when.as_ref().is_none_or(|c| c.holds(platform));
        Ok(Unit {
            decl: decl.clone(),
            module: module.id.clone(),
            root: module.root.clone(),
            available,
            offered: false,
            packages,
            aur,
            hooks,
            option_roots: merged.option_roots.clone(),
            extended_by: merged.extended_by.clone(),
        })
    }
}

fn check_target(unit: &str, file: &FileEntry) -> Result<(), RegistryError> {
    let target = &file.target;
    if target.is_empty() || target.split('/').any(|part| part == "..") {
        return Err(RegistryError::BadTarget {
            unit: unit.into(),
            target: target.clone(),
        });
    }
    if file.is_system() && (file.mode != Mode::Copy || file.permissions.is_none()) {
        return Err(RegistryError::SystemFile {
            unit: unit.into(),
            target: target.clone(),
        });
    }
    if file.permissions.is_some() && file.mode == Mode::Symlink {
        return Err(RegistryError::PermissionsOnLink {
            unit: unit.into(),
            target: target.clone(),
        });
    }
    Ok(())
}

fn check_input(unit: &str, input: &Input) -> Result<(), RegistryError> {
    let error = |make: fn(String, String) -> RegistryError| make(unit.into(), input.id.clone());
    if !valid_id(&input.id, '_') {
        return Err(error(|unit, input| RegistryError::BadInputId {
            unit,
            input,
        }));
    }
    if input.prompt.trim().is_empty() {
        return Err(error(|unit, input| RegistryError::InputPrompt {
            unit,
            input,
        }));
    }
    match input.kind {
        InputKind::Choice => {
            if input.options.is_empty() {
                return Err(error(|unit, input| RegistryError::InputWithoutOptions {
                    unit,
                    input,
                }));
            }
            if let Some(default) = &input.default {
                if !input.custom && !input.options.iter().any(|o| o.value == *default) {
                    return Err(RegistryError::InputDefault {
                        unit: unit.into(),
                        input: input.id.clone(),
                        value: default.clone(),
                    });
                }
            }
        }
        kind => {
            if !input.options.is_empty() || input.custom {
                return Err(error(|unit, input| RegistryError::NotAChoice {
                    unit,
                    input,
                }));
            }
            if kind == InputKind::Bool {
                if let Some(default) = &input.default {
                    if default != "true" && default != "false" {
                        return Err(RegistryError::InputFlag {
                            unit: unit.into(),
                            input: input.id.clone(),
                            value: default.clone(),
                        });
                    }
                }
            }
        }
    }
    if input.required && input.kind != InputKind::Text {
        return Err(error(|unit, input| RegistryError::NotAText { unit, input }));
    }
    Ok(())
}

/// The `{id}` placeholders of a source path.
pub(crate) fn placeholders(source: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = source;
    while let Some(start) = rest.find('{') {
        let Some(len) = rest[start..].find('}') else {
            break;
        };
        out.push(rest[start + 1..start + len].to_string());
        rest = &rest[start + len + 1..];
    }
    out
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::declarations::{Hook, InputOption, Package};
    use crate::platform::{Condition, Expected};
    use crate::{Profile, Profiles, Reason, Selection};

    pub(crate) fn platform() -> Platform {
        Platform {
            distro: "arch".into(),
            arch: "x86_64".into(),
            cpu: "intel".into(),
            gpu: vec!["nvidia".into()],
            vm: false,
            apple_silicon: false,
            bootloader: "grub".into(),
            filesystems: vec!["ext4".into()],
        }
    }

    pub(crate) fn when(fact: &str, value: &str) -> Condition {
        Condition::new([(fact.to_string(), Expected::Words(vec![value.to_string()]))]).unwrap()
    }

    pub(crate) fn unit(id: &str) -> UnitDeclaration {
        UnitDeclaration {
            id: id.into(),
            name: format!("{id} unit"),
            packages: vec![Package {
                name: format!("{id}-pkg"),
                when: None,
            }],
            ..Default::default()
        }
    }

    pub(crate) fn module(id: &str, units: Vec<UnitDeclaration>) -> ModuleDeclaration {
        ModuleDeclaration {
            id: id.into(),
            name: format!("{id} module"),
            about: None,
            root: PathBuf::from("/repo"),
            units,
            fragments: Vec::new(),
        }
    }

    fn fragment(unit: &str, merge: Merge) -> Fragment {
        Fragment {
            unit: unit.into(),
            merge,
            when: None,
            packages: Vec::new(),
            aur: Vec::new(),
            services: Vec::new(),
            files: Vec::new(),
            variants: Vec::new(),
            inputs: Vec::new(),
            hooks: Vec::new(),
            choice: None,
        }
    }

    fn file(source: &str, target: &str) -> FileEntry {
        FileEntry {
            source: source.into(),
            target: target.into(),
            mode: Mode::Copy,
            contents: false,
            backup: false,
            permissions: None,
        }
    }

    fn variant(id: &str, options: &[&str]) -> Variant {
        Variant {
            id: id.into(),
            name: id.to_uppercase(),
            options: options.iter().map(|o| o.to_string()).collect(),
            default: None,
        }
    }

    #[test]
    fn a_choice_between_parts_is_checked_and_one_part_comes_with_the_unit() {
        let platform = Platform {
            distro: "arch".into(),
            arch: "x86_64".into(),
            ..Default::default()
        };
        let pkg = |name: &str| {
            vec![Package {
                name: name.into(),
                when: None,
            }]
        };
        let part = |id: &str| UnitDeclaration {
            id: id.into(),
            name: id.to_uppercase(),
            parent: Some("shell".into()),
            packages: pkg(id),
            ..Default::default()
        };
        let shell = UnitDeclaration {
            id: "shell".into(),
            name: "Shell".into(),
            packages: pkg("starship"),
            choice: Some(Choice {
                parts: vec!["zsh".into(), "fish".into()],
                default: "zsh".into(),
            }),
            ..Default::default()
        };
        let term = module(
            "term",
            vec![shell.clone(), part("zsh"), part("fish"), part("fastfetch")],
        );
        let reg = Registry::new(
            Declarations {
                modules: vec![term.clone()],
            },
            &platform,
        )
        .unwrap();
        assert!(reg.unit("zsh").unwrap().offered() && reg.unit("fish").unwrap().offered());
        assert_eq!(reg.choice_of("fish").map(|(u, _)| u.id()), Some("shell"));
        assert!(reg.choice_of("fastfetch").is_none());

        // The plan: the default part comes with the unit, a picked one replaces it
        let mut selection = Selection::new();
        selection.select("shell");
        let plan = crate::plan::build(&reg, &selection);
        let units: Vec<&str> = plan.steps().iter().map(|s| s.unit()).collect();
        assert_eq!(units, ["shell", "zsh"]);
        assert_eq!(
            plan.step("zsh").unwrap().reason(),
            &Reason::DefaultOf("shell".into())
        );
        selection.select("fish");
        let plan = crate::plan::build(&reg, &selection);
        let units: Vec<&str> = plan.steps().iter().map(|s| s.unit()).collect();
        assert_eq!(units, ["shell", "fish"]);

        // Profiles: a pattern keeps the default, a name picks
        let profiles = Profiles::new([
            Profile {
                name: "full".into(),
                units: vec!["*".into()],
                ..Default::default()
            },
            Profile {
                name: "fishy".into(),
                extends: Some("full".into()),
                units: vec!["fish".into()],
                ..Default::default()
            },
        ])
        .unwrap();
        let full = profiles.resolve("full", &reg).unwrap().selection;
        assert!(full.contains("zsh") && !full.contains("fish") && full.contains("fastfetch"));
        let fishy = profiles.resolve("fishy", &reg).unwrap().selection;
        assert!(fishy.contains("fish") && !fishy.contains("zsh"));

        // The mistakes
        let err = |units: Vec<UnitDeclaration>| {
            Registry::new(
                Declarations {
                    modules: vec![module("term", units)],
                },
                &platform,
            )
            .unwrap_err()
        };
        let mut small = shell.clone();
        small.choice = Some(Choice {
            parts: vec!["zsh".into()],
            default: "zsh".into(),
        });
        assert!(matches!(
            err(vec![small, part("zsh"), part("fish")]),
            RegistryError::ChoiceTooSmall { .. }
        ));
        let mut stranger = shell.clone();
        stranger.choice = Some(Choice {
            parts: vec!["zsh".into(), "fastfetch".into()],
            default: "zsh".into(),
        });
        let mut loose = part("fastfetch");
        loose.parent = None;
        assert!(matches!(
            err(vec![stranger, part("zsh"), part("fish"), loose]),
            RegistryError::ChoiceNotAPart { .. }
        ));
        let mut odd = shell.clone();
        odd.choice = Some(Choice {
            parts: vec!["zsh".into(), "fish".into()],
            default: "bash".into(),
        });
        assert!(matches!(
            err(vec![odd, part("zsh"), part("fish")]),
            RegistryError::ChoiceDefault { .. }
        ));
        let mut needy = shell.clone();
        needy.requires = vec!["zsh".into()];
        assert!(matches!(
            err(vec![needy, part("zsh"), part("fish")]),
            RegistryError::ChoiceRequired { .. }
        ));
    }

    #[test]
    fn fragments_extend_and_override_units_of_earlier_modules() {
        let platform = Platform {
            distro: "arch".into(),
            arch: "x86_64".into(),
            ..Default::default()
        };
        let mut app = UnitDeclaration {
            id: "app".into(),
            name: "App".into(),
            packages: vec![Package {
                name: "app".into(),
                when: None,
            }],
            files: vec![file("files/x/{theme}", ".config/x")],
            variants: vec![variant("theme", &["a", "b"])],
            hooks: vec![Hook {
                run: "setup".into(),
                when: None,
            }],
            ..Default::default()
        };
        let alpha = module("alpha", vec![app.clone()]);
        let mut extend = fragment("app", Merge::Extend);
        extend.files = vec![
            file("files/local", ".local"),
            file("files/k/{work}.lua", ".config/x"),
        ];
        extend.variants = vec![variant("work", &["l", "d"])];
        extend.hooks = vec![Hook {
            run: "extra".into(),
            when: None,
        }];
        extend.packages = vec![Package {
            name: "more".into(),
            when: None,
        }];
        let mut beta = module("beta", Vec::new());
        beta.root = PathBuf::from("/beta");
        beta.fragments = vec![extend.clone()];
        let reg = Registry::new(
            Declarations {
                modules: vec![alpha.clone(), beta.clone()],
            },
            &platform,
        )
        .unwrap();
        let unit = reg.unit("app").unwrap();
        let sources: Vec<&str> = unit.files().iter().map(|f| f.source.as_str()).collect();
        assert_eq!(
            sources,
            ["/beta/files/local", "/beta/files/k/{work}.lua"],
            "the same target is replaced"
        );
        let variants: Vec<&str> = unit.variants().iter().map(|v| v.id.as_str()).collect();
        assert_eq!(
            variants,
            ["work"],
            "the variant of the replaced file is gone"
        );
        assert_eq!(unit.hooks().collect::<Vec<_>>(), ["setup", "extra"]);
        assert_eq!(unit.hook_runs()[0].module_root, PathBuf::from("/repo"));
        assert_eq!(unit.hook_runs()[1].module_root, PathBuf::from("/beta"));
        assert_eq!(unit.packages(), ["app", "more"]);
        assert_eq!(unit.extended_by(), ["beta"]);

        // More options for a variant of the unit: their files live in the
        // fragment's module
        let mut more = fragment("app", Merge::Extend);
        more.variants = vec![Variant {
            id: "theme".into(),
            name: String::new(),
            options: vec!["c".into()],
            default: Some("c".into()),
        }];
        let mut epsilon = module("epsilon", Vec::new());
        epsilon.root = PathBuf::from("/epsilon");
        epsilon.fragments = vec![more.clone()];
        let reg = Registry::new(
            Declarations {
                modules: vec![alpha.clone(), epsilon.clone()],
            },
            &platform,
        )
        .unwrap();
        let unit = reg.unit("app").unwrap();
        let theme = unit.variant("theme").unwrap();
        assert_eq!(theme.options, ["a", "b", "c"]);
        assert_eq!(theme.default.as_deref(), Some("c"));
        assert_eq!(theme.name, "THEME", "the name stays the unit's");
        assert_eq!(unit.option_root("theme", "c"), Some(Path::new("/epsilon")));
        assert_eq!(unit.option_root("theme", "a"), None);
        epsilon.fragments[0].variants[0].options = vec!["a".into()];
        assert!(matches!(
            Registry::new(
                Declarations {
                    modules: vec![alpha.clone(), epsilon]
                },
                &platform
            )
            .unwrap_err(),
            RegistryError::Repeated { .. }
        ));
        let mut nameless = beta.clone();
        nameless.fragments[0].variants[0].name = String::new();
        assert!(matches!(
            Registry::new(
                Declarations {
                    modules: vec![alpha.clone(), nameless]
                },
                &platform
            )
            .unwrap_err(),
            RegistryError::VariantName { .. }
        ));

        // Override: the configuration is the fragment's, the packages stay
        let mut override_ = fragment("app", Merge::Override);
        override_.files = vec![file("files/mine", ".config/x")];
        override_.hooks = vec![Hook {
            run: "mine".into(),
            when: None,
        }];
        let mut gamma = module("gamma", Vec::new());
        gamma.root = PathBuf::from("/gamma");
        gamma.fragments = vec![override_.clone()];
        let reg = Registry::new(
            Declarations {
                modules: vec![alpha.clone(), gamma.clone()],
            },
            &platform,
        )
        .unwrap();
        let unit = reg.unit("app").unwrap();
        assert_eq!(unit.files()[0].source, "/gamma/files/mine");
        assert!(unit.variants().is_empty());
        assert_eq!(unit.hooks().collect::<Vec<_>>(), ["mine"]);
        assert_eq!(unit.packages(), ["app"]);

        // A fragment for other machines changes nothing
        let mut elsewhere = beta.clone();
        elsewhere.fragments[0].when = Some(
            Condition::new([("arch".to_string(), Expected::Words(vec!["aarch64".into()]))])
                .unwrap(),
        );
        let reg = Registry::new(
            Declarations {
                modules: vec![alpha.clone(), elsewhere],
            },
            &platform,
        )
        .unwrap();
        assert_eq!(
            reg.unit("app").unwrap().files()[0].source,
            "files/x/{theme}"
        );
        assert!(reg.unit("app").unwrap().extended_by().is_empty());

        // The mistakes
        let mut lost = beta.clone();
        lost.fragments[0].unit = "nope".into();
        assert!(matches!(
            Registry::new(
                Declarations {
                    modules: vec![alpha.clone(), lost]
                },
                &platform
            )
            .unwrap_err(),
            RegistryError::UnknownExtended { .. }
        ));
        let mut own = alpha.clone();
        own.fragments = vec![fragment("app", Merge::Extend)];
        assert!(matches!(
            Registry::new(Declarations { modules: vec![own] }, &platform).unwrap_err(),
            RegistryError::ExtendedOwnModule { .. }
        ));
        assert!(
            matches!(
                Registry::new(
                    Declarations {
                        modules: vec![beta.clone(), alpha.clone()]
                    },
                    &platform
                )
                .unwrap_err(),
                RegistryError::UnknownExtended { .. }
            ),
            "the extended unit must come first"
        );
        let mut delta = gamma.clone();
        delta.id = "delta".into();
        assert!(matches!(
            Registry::new(
                Declarations {
                    modules: vec![alpha.clone(), gamma, delta]
                },
                &platform
            )
            .unwrap_err(),
            RegistryError::OverriddenTwice { .. }
        ));
        app.files.clear();
        app.variants.clear();
        let _ = app;
    }

    #[test]
    fn a_fragment_adds_parts_to_a_choice_or_replaces_it() {
        use crate::declarations::ChoiceChange;
        let platform = Platform {
            distro: "arch".into(),
            arch: "x86_64".into(),
            ..Default::default()
        };
        let part = |id: &str| UnitDeclaration {
            id: id.into(),
            name: id.to_uppercase(),
            parent: Some("shell".into()),
            requires: vec!["shell".into()],
            packages: vec![Package {
                name: id.into(),
                when: None,
            }],
            ..Default::default()
        };
        let shell = UnitDeclaration {
            id: "shell".into(),
            name: "Shell".into(),
            packages: vec![Package {
                name: "starship".into(),
                when: None,
            }],
            choice: Some(Choice {
                parts: vec!["zsh".into(), "fish".into()],
                default: "zsh".into(),
            }),
            ..Default::default()
        };
        let term = module("term", vec![shell.clone(), part("zsh"), part("fish")]);
        let mut extend = fragment("shell", Merge::Extend);
        extend.choice = Some(ChoiceChange {
            parts: vec!["nushell".into()],
            default: Some("nushell".into()),
        });
        // The part is a unit of the private module, under the public parent
        let mut work = module("work", vec![part("nushell")]);
        work.fragments = vec![extend.clone()];
        let reg = Registry::new(
            Declarations {
                modules: vec![term.clone(), work.clone()],
            },
            &platform,
        )
        .unwrap();
        let choice = reg.unit("shell").unwrap().choice().unwrap();
        assert_eq!(choice.parts, ["zsh", "fish", "nushell"]);
        assert_eq!(choice.default, "nushell");
        assert_eq!(reg.choice_of("nushell").map(|(u, _)| u.id()), Some("shell"));
        assert_eq!(
            reg.parts("shell").map(Unit::id).collect::<Vec<_>>(),
            ["zsh", "fish", "nushell"]
        );
        let mut selection = Selection::new();
        selection.select("shell");
        let plan = crate::plan::build(&reg, &selection);
        let units: Vec<&str> = plan.steps().iter().map(|s| s.unit()).collect();
        assert_eq!(
            units,
            ["shell", "nushell"],
            "the new default comes with shell"
        );
        assert_eq!(
            plan.step("nushell").unwrap().reason(),
            &Reason::DefaultOf("shell".into())
        );

        // The default alone, the parts untouched
        work.fragments[0].choice = Some(ChoiceChange {
            parts: Vec::new(),
            default: Some("fish".into()),
        });
        let reg = Registry::new(
            Declarations {
                modules: vec![term.clone(), work.clone()],
            },
            &platform,
        )
        .unwrap();
        let choice = reg.unit("shell").unwrap().choice().unwrap();
        assert_eq!((choice.parts.len(), choice.default.as_str()), (2, "fish"));
        assert!(
            reg.unit("nushell").unwrap().offered() && reg.choice_of("nushell").is_none(),
            "a part outside the choice is an optional part"
        );

        // Override: the choice in full, or the unit's when none is given
        let mut replace = fragment("shell", Merge::Override);
        replace.choice = Some(ChoiceChange {
            parts: vec!["nushell".into(), "fish".into()],
            default: Some("fish".into()),
        });
        work.fragments = vec![replace.clone()];
        let reg = Registry::new(
            Declarations {
                modules: vec![term.clone(), work.clone()],
            },
            &platform,
        )
        .unwrap();
        let choice = reg.unit("shell").unwrap().choice().unwrap();
        assert_eq!(choice.parts, ["nushell", "fish"]);
        assert!(reg.choice_of("zsh").is_none());
        work.fragments[0].choice = None;
        let reg = Registry::new(
            Declarations {
                modules: vec![term.clone(), work.clone()],
            },
            &platform,
        )
        .unwrap();
        assert_eq!(
            reg.unit("shell").unwrap().choice().unwrap().parts,
            ["zsh", "fish"]
        );

        // The mistakes
        let err = |work: ModuleDeclaration| {
            Registry::new(
                Declarations {
                    modules: vec![term.clone(), work],
                },
                &platform,
            )
            .unwrap_err()
        };
        let mut nodefault = work.clone();
        nodefault.fragments = vec![replace.clone()];
        nodefault.fragments[0].choice.as_mut().unwrap().default = None;
        assert!(matches!(
            err(nodefault),
            RegistryError::ChoiceWithoutDefault { .. }
        ));
        let mut again = work.clone();
        again.fragments = vec![extend.clone()];
        again.fragments[0].choice.as_mut().unwrap().parts = vec!["fish".into()];
        assert!(matches!(
            err(again),
            RegistryError::Repeated {
                list: "choice parts",
                ..
            }
        ));
        let mut choiceless = work.clone();
        choiceless.fragments = vec![extend.clone()];
        choiceless.fragments[0].unit = "zsh".into();
        choiceless.units[0].parent = Some("zsh".into());
        assert!(matches!(err(choiceless), RegistryError::NoChoice { .. }));
        let mut late = term.clone();
        late.units.push(part("nushell"));
        late.units.last_mut().unwrap().parent = Some("later".into());
        let later = module("work", vec![unit("later")]);
        assert!(matches!(
            Registry::new(
                Declarations {
                    modules: vec![late, later],
                },
                &platform
            )
            .unwrap_err(),
            RegistryError::ParentInLaterModule { .. }
        ));
    }

    /// Two modules: alpha (base, always; quick; slow requires quick; arm
    /// on aarch64 only) and beta (elem with parts: part required, extra
    /// optional; late, early after late).
    pub(crate) fn declarations() -> Declarations {
        let mut base = unit("base");
        base.always = true;
        let mut slow = unit("slow");
        slow.requires = vec!["quick".into()];
        let mut arm = unit("arm");
        arm.when = Some(when("arch", "aarch64"));
        let mut elem = unit("elem");
        elem.requires = vec!["part".into()];
        let mut part = unit("part");
        part.parent = Some("elem".into());
        let mut extra = unit("extra");
        extra.parent = Some("elem".into());
        let mut early = unit("early");
        early.after = vec!["late".into()];
        Declarations {
            modules: vec![
                module("alpha", vec![base, unit("quick"), slow, arm]),
                module("beta", vec![elem, part, extra, early, unit("late")]),
            ],
        }
    }

    #[test]
    fn availability_and_offers_follow_the_platform_and_the_parents() {
        let reg = Registry::new(declarations(), &platform()).unwrap();
        assert_eq!(reg.units().count(), 9);
        assert!(!reg.unit("arm").unwrap().available(), "aarch64 only");
        assert!(!reg.unit("arm").unwrap().offered());
        assert!(
            reg.unit("base").unwrap().available() && !reg.unit("base").unwrap().offered(),
            "always units are not offered"
        );
        assert!(
            !reg.unit("part").unwrap().offered(),
            "a part its parent requires comes with it"
        );
        assert!(
            reg.unit("extra").unwrap().offered(),
            "the other parts are offered"
        );
        assert_eq!(
            reg.parts("elem").map(Unit::id).collect::<Vec<_>>(),
            ["part", "extra"]
        );
        assert_eq!(
            reg.required_by("quick").map(Unit::id).collect::<Vec<_>>(),
            ["slow"]
        );
        assert_eq!(reg.position("late"), Some(8));
    }

    #[test]
    fn packages_and_hooks_are_kept_for_the_machine() {
        let mut nvidia = unit("nvidia");
        nvidia.packages = vec![
            Package {
                name: "nvidia-utils".into(),
                when: None,
            },
            Package {
                name: "lib32-nvidia-utils".into(),
                when: Some(when("arch", "x86_64")),
            },
            Package {
                name: "arm-only".into(),
                when: Some(when("arch", "aarch64")),
            },
        ];
        nvidia.hooks = vec![
            Hook {
                run: "setup".into(),
                when: None,
            },
            Hook {
                run: "build".into(),
                when: Some(when("arch", "aarch64")),
            },
        ];
        let reg = Registry::new(
            Declarations {
                modules: vec![module("hw", vec![nvidia])],
            },
            &platform(),
        )
        .unwrap();
        let unit = reg.unit("nvidia").unwrap();
        assert_eq!(unit.packages(), ["nvidia-utils", "lib32-nvidia-utils"]);
        assert_eq!(unit.hooks().collect::<Vec<_>>(), ["setup"]);
        assert_eq!(unit.declaration().hooks.len(), 2);
    }

    fn error_of(units: Vec<UnitDeclaration>) -> RegistryError {
        Registry::new(
            Declarations {
                modules: vec![module("m", units)],
            },
            &platform(),
        )
        .unwrap_err()
    }

    #[test]
    fn declarations_are_checked() {
        assert_eq!(
            error_of(vec![unit("Bad_Id")]),
            RegistryError::BadUnitId("Bad_Id".into())
        );
        assert_eq!(
            Registry::new(
                Declarations {
                    modules: vec![module("a", vec![unit("x")]), module("b", vec![unit("x")])]
                },
                &platform()
            )
            .unwrap_err(),
            RegistryError::DuplicateUnit {
                id: "x".into(),
                module: "b".into(),
                other: "a".into()
            }
        );
        let mut orphan = unit("orphan");
        orphan.parent = Some("nobody".into());
        assert_eq!(
            error_of(vec![orphan]),
            RegistryError::UnknownParent {
                unit: "orphan".into(),
                parent: "nobody".into()
            }
        );
        let mut needy = unit("needy");
        needy.requires = vec!["ghost".into()];
        assert_eq!(
            error_of(vec![needy]),
            RegistryError::UnknownReference {
                unit: "needy".into(),
                relation: "requires",
                target: "ghost".into()
            }
        );
        let mut a = unit("a");
        a.requires = vec!["b".into()];
        let mut b = unit("b");
        b.after = vec!["a".into()];
        assert_eq!(
            error_of(vec![a, b]),
            RegistryError::Cycle(vec!["a".into(), "b".into(), "a".into()])
        );
        let mut empty = unit("empty");
        empty.packages.clear();
        assert_eq!(
            error_of(vec![empty]),
            RegistryError::NothingToDo("empty".into())
        );
        let mut dup = unit("dup");
        dup.packages.push(Package {
            name: "dup-pkg".into(),
            when: None,
        });
        assert_eq!(
            error_of(vec![dup]),
            RegistryError::Repeated {
                unit: "dup".into(),
                list: "packages",
                name: "dup-pkg".into()
            }
        );
    }

    #[test]
    fn files_variants_and_inputs_are_checked() {
        let mut themed = unit("themed");
        themed.files = vec![FileEntry {
            source: ".config/x/{theme}".into(),
            target: ".config/x".into(),
            mode: Mode::Symlink,
            contents: false,
            backup: true,
            permissions: None,
        }];
        assert_eq!(
            error_of(vec![themed.clone()]),
            RegistryError::UnknownPlaceholder {
                unit: "themed".into(),
                path: ".config/x/{theme}".into(),
                placeholder: "theme".into()
            }
        );
        themed.variants = vec![Variant {
            id: "theme".into(),
            name: "Theme".into(),
            options: vec!["a".into()],
            default: Some("z".into()),
        }];
        assert_eq!(
            error_of(vec![themed.clone()]),
            RegistryError::VariantDefault {
                unit: "themed".into(),
                variant: "theme".into(),
                option: "z".into()
            }
        );
        themed.variants[0].default = None;
        themed.variants.push(Variant {
            id: "unused".into(),
            name: "Unused".into(),
            options: vec!["a".into()],
            default: None,
        });
        assert_eq!(
            error_of(vec![themed.clone()]),
            RegistryError::UnusedVariant {
                unit: "themed".into(),
                variant: "unused".into()
            }
        );
        themed.variants.pop();
        themed.files[0].target = "../etc".into();
        assert_eq!(
            error_of(vec![themed.clone()]),
            RegistryError::BadTarget {
                unit: "themed".into(),
                target: "../etc".into()
            }
        );
        themed.files[0].target = ".config/x".into();
        themed.files[0].permissions = Some(0o755);
        assert_eq!(
            error_of(vec![themed.clone()]),
            RegistryError::PermissionsOnLink {
                unit: "themed".into(),
                target: ".config/x".into()
            }
        );
        themed.files[0].permissions = None;
        themed.files[0].target = "/etc/samba/nas.cred".into();
        assert_eq!(
            error_of(vec![themed.clone()]),
            RegistryError::SystemFile {
                unit: "themed".into(),
                target: "/etc/samba/nas.cred".into()
            }
        );
        themed.files[0].mode = Mode::Copy;
        themed.files[0].permissions = Some(0o600);
        assert!(
            Registry::new(
                Declarations {
                    modules: vec![module("m", vec![themed.clone()])]
                },
                &platform()
            )
            .is_ok(),
            "a system file is copied with permissions"
        );
        themed.files[0].mode = Mode::Symlink;
        themed.files[0].permissions = None;
        themed.files[0].target = ".config/x".into();
        assert!(
            Registry::new(
                Declarations {
                    modules: vec![module("m", vec![themed])]
                },
                &platform()
            )
            .is_ok()
        );

        let mut asking = unit("asking");
        asking.inputs = vec![Input {
            id: "repo".into(),
            prompt: "Repo".into(),
            kind: InputKind::Choice,
            ..Default::default()
        }];
        assert_eq!(
            error_of(vec![asking.clone()]),
            RegistryError::InputWithoutOptions {
                unit: "asking".into(),
                input: "repo".into()
            }
        );
        asking.inputs[0].options = vec![InputOption {
            name: "A".into(),
            value: "a".into(),
        }];
        asking.inputs[0].default = Some("b".into());
        assert_eq!(
            error_of(vec![asking.clone()]),
            RegistryError::InputDefault {
                unit: "asking".into(),
                input: "repo".into(),
                value: "b".into()
            }
        );
        asking.inputs[0].custom = true;
        assert!(
            Registry::new(
                Declarations {
                    modules: vec![module("m", vec![asking.clone()])]
                },
                &platform()
            )
            .is_ok(),
            "custom allows a default outside the options"
        );
        asking.inputs = vec![Input {
            id: "fido".into(),
            prompt: "FIDO?".into(),
            kind: InputKind::Bool,
            default: Some("yes".into()),
            ..Default::default()
        }];
        assert_eq!(
            error_of(vec![asking.clone()]),
            RegistryError::InputFlag {
                unit: "asking".into(),
                input: "fido".into(),
                value: "yes".into()
            }
        );
        asking.inputs = vec![Input {
            id: "fido".into(),
            prompt: "FIDO?".into(),
            kind: InputKind::Bool,
            required: true,
            ..Default::default()
        }];
        assert_eq!(
            error_of(vec![asking]),
            RegistryError::NotAText {
                unit: "asking".into(),
                input: "fido".into()
            }
        );
    }

    #[test]
    fn placeholders_are_read() {
        assert_eq!(
            placeholders(".config/hypr/{keybinds}/{keyboard}.lua"),
            ["keybinds", "keyboard"]
        );
        assert!(placeholders(".config/plain").is_empty());
    }
}
