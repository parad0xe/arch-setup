use std::io;
use std::path::PathBuf;

use model::ConditionError;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum RepoError {
    #[error("{path} is not a setup repository: {reason}")]
    NotARepository { path: PathBuf, reason: String },
    #[error("{path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: io::Error,
    },
    #[error("{path}: {source}")]
    Toml {
        path: PathBuf,
        #[source]
        source: toml::de::Error,
    },
    #[error("{path}: {source}")]
    TomlWrite {
        path: PathBuf,
        #[source]
        source: toml::ser::Error,
    },
    #[error("{path}: unit {unit}: {source}")]
    Condition {
        path: PathBuf,
        unit: String,
        #[source]
        source: ConditionError,
    },
    #[error(
        "{path}: unit {unit}: the property {fact} must be true or false, a word, or a list of words"
    )]
    ConditionValue {
        path: PathBuf,
        unit: String,
        fact: String,
    },
    #[error("{path}: unit {unit}: the default of input {input} must be text, or true or false")]
    InputDefault {
        path: PathBuf,
        unit: String,
        input: String,
    },
    #[error(
        "{path}: the folder name {name} is not a module id (lower-case letters, digits and dashes)"
    )]
    ModuleId { path: PathBuf, name: String },
    #[error(
        "{path}: a module is a folder modules/<id> holding module.toml, hooks.sh and its files"
    )]
    ModuleLayout { path: PathBuf },
    #[error("{path}: a [[unit]] has an id, or extends or overrides a unit: one of the three")]
    FragmentKeys { path: PathBuf },
    #[error("{path}: the fragment of {unit} cannot set {field}: that belongs to the unit")]
    FragmentField {
        path: PathBuf,
        unit: String,
        field: &'static str,
    },
    #[error("{path}: unit {unit}: the name is missing")]
    MissingName { path: PathBuf, unit: String },
    #[error("{path}: unit {unit}: the choice has no default")]
    ChoiceDefault { path: PathBuf, unit: String },
    #[error("{path}: unit {unit}: the permissions {value} are not octal digits (600, 755...)")]
    Permissions {
        path: PathBuf,
        unit: String,
        value: String,
    },
    #[error("module {id} is declared in {first} and in {second}")]
    DuplicateModule {
        id: String,
        first: PathBuf,
        second: PathBuf,
    },
    #[error("unit {unit}: the source {file} does not exist in the repository")]
    MissingSource { unit: String, file: String },
    #[error("unit {unit}: {file} is a file; contents applies to a folder")]
    ContentsOnFile { unit: String, file: String },
    #[error("unit {unit}: hooks declared, but {script} does not exist")]
    ScriptMissing { unit: String, script: PathBuf },
    #[error("unit {unit}: the hook {function} is not a function of {script}")]
    HookUndefined {
        unit: String,
        function: String,
        script: PathBuf,
    },
    #[error("{path}: the input {key} must be text, or true or false")]
    ProfileInput { path: PathBuf, key: String },
    #[error("{0} is not a profile name: lower-case letters, digits, dashes and underscores")]
    ProfileName(String),
}
