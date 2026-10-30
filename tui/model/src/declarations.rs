//! What a reader finds in the manifests, before validation: plain values.

use std::path::PathBuf;

use crate::platform::Condition;

/// The modules of a repository, in their order.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Declarations {
    pub modules: Vec<ModuleDeclaration>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ModuleDeclaration {
    /// The file name of the module.
    pub id: String,
    pub name: String,
    pub about: Option<String>,
    /// Its folder, `modules/<id>` of the repository declaring it: the
    /// sources of its files and its hook script are there.
    pub root: PathBuf,
    pub units: Vec<UnitDeclaration>,
    /// What this module adds to, or replaces in, units of modules read
    /// before it.
    pub fragments: Vec<Fragment>,
}

/// How a fragment changes the unit it names.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Merge {
    /// Adds to the unit; a file whose target the unit already deploys
    /// replaces that entry.
    Extend,
    /// Replaces the files, variants, inputs and hooks of the unit; its
    /// packages and services stay.
    Override,
}

/// A `[[unit]]` table with `extend` or `override` in place of an `id`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Fragment {
    /// The unit it changes, of a module read before.
    pub unit: String,
    pub merge: Merge,
    /// Applies on these machines only.
    pub when: Option<Condition>,
    pub packages: Vec<Package>,
    pub aur: Vec<Package>,
    pub services: Vec<Service>,
    pub files: Vec<FileEntry>,
    pub variants: Vec<Variant>,
    pub inputs: Vec<Input>,
    pub hooks: Vec<Hook>,
    /// With `extend`, more parts for the choice of the unit, and perhaps
    /// another default; with `override`, the choice in full.
    pub choice: Option<ChoiceChange>,
}

/// What a fragment does to the choice of the unit it names.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChoiceChange {
    pub parts: Vec<String>,
    /// Required when the choice is replaced.
    pub default: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UnitDeclaration {
    pub id: String,
    pub name: String,
    pub about: Option<String>,
    pub parent: Option<String>,
    pub always: bool,
    pub attended: bool,
    pub when: Option<Condition>,
    pub requires: Vec<String>,
    pub after: Vec<String>,
    pub packages: Vec<Package>,
    pub aur: Vec<Package>,
    pub services: Vec<Service>,
    pub files: Vec<FileEntry>,
    pub variants: Vec<Variant>,
    pub inputs: Vec<Input>,
    pub hooks: Vec<Hook>,
    /// Exclusive parts: exactly one of them comes with the unit.
    pub choice: Option<Choice>,
}

/// A choice between parts of a unit: one of them is in the run when the
/// unit is, the default when none is picked.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Choice {
    pub parts: Vec<String>,
    pub default: String,
}

/// A package, for some machines only when it has a condition.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Package {
    pub name: String,
    pub when: Option<Condition>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Service {
    pub name: String,
    /// Started as well.
    pub now: bool,
    /// Replaces a service of the same role.
    pub force: bool,
}

/// How a file or folder of the repository goes into the home folder: a
/// copy, or a symbolic link to the repository.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Mode {
    Symlink,
    #[default]
    Copy,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileEntry {
    /// Relative to the module's folder (absolute once a fragment of another
    /// module brought it); may name variants as `{id}`.
    pub source: String,
    /// From the home folder; absolute for a system file, copied with sudo.
    pub target: String,
    pub mode: Mode,
    /// For a folder: each of its entries goes into the target folder.
    pub contents: bool,
    /// A different existing file is kept as .bak instead of replaced.
    pub backup: bool,
    /// The permissions of the copied files (octal, e.g. 0o600).
    pub permissions: Option<u32>,
}

impl FileEntry {
    /// Outside the home folder: copied with sudo, owned by root.
    pub fn is_system(&self) -> bool {
        self.target.starts_with('/')
    }
}

/// A choice between versions of a file or folder. In a fragment, a variant
/// with the id of one of the unit's adds its options to it (the files of
/// these options are in the fragment's module, at the same relative path);
/// its name is then not needed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Variant {
    pub id: String,
    pub name: String,
    pub options: Vec<String>,
    /// The option used when none is picked: "default" when the options
    /// have it, else the first, when not given.
    pub default: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InputKind {
    #[default]
    Text,
    Bool,
    /// Not echoed, not logged.
    Secret,
    Choice,
}

/// A proposed answer of a choice input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InputOption {
    pub name: String,
    pub value: String,
}

/// A question answered before the run.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Input {
    pub id: String,
    pub prompt: String,
    pub kind: InputKind,
    /// The answer when none is given, as text (`true`/`false` for a bool).
    pub default: Option<String>,
    /// An empty answer is refused (text only).
    pub required: bool,
    /// The proposed answers (choice only).
    pub options: Vec<InputOption>,
    /// A value outside the options may be typed (choice only).
    pub custom: bool,
}

/// A function of the module's script, run after the declared parts.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hook {
    pub run: String,
    pub when: Option<Condition>,
}
