//! The profile files (`<name>.toml`): reading a folder of them, writing one.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use model::{InputValue, Profile};
use serde::{Deserialize, Serialize};

use crate::error::RepoError;
use crate::repository::{read, read_dir};

#[derive(Deserialize, Serialize, Default)]
#[serde(deny_unknown_fields)]
struct ProfileFile {
    #[serde(skip_serializing_if = "Option::is_none")]
    about: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    extends: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    units: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    exclude: Vec<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    variants: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    inputs: BTreeMap<String, toml::Value>,
}

/// The profiles of a folder, in file name order. A missing folder holds
/// none.
pub fn read_profiles(dir: &Path) -> Result<Vec<Profile>, RepoError> {
    if !dir.is_dir() {
        return Ok(Vec::new());
    }
    let mut paths: Vec<PathBuf> = read_dir(dir)?
        .into_iter()
        .filter(|p| p.extension().is_some_and(|e| e == "toml"))
        .collect();
    paths.sort();
    paths.iter().map(|path| read_profile(path)).collect()
}

fn read_profile(path: &Path) -> Result<Profile, RepoError> {
    let name = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or_default()
        .to_string();
    let file: ProfileFile = toml::from_str(&read(path)?).map_err(|source| RepoError::Toml {
        path: path.to_path_buf(),
        source,
    })?;
    let mut inputs = BTreeMap::new();
    for (key, value) in file.inputs {
        let value = match value {
            toml::Value::String(text) => InputValue::Text(text),
            toml::Value::Boolean(flag) => InputValue::Flag(flag),
            _ => {
                return Err(RepoError::ProfileInput {
                    path: path.to_path_buf(),
                    key,
                });
            }
        };
        inputs.insert(key, value);
    }
    Ok(Profile {
        name,
        about: file.about,
        extends: file.extends,
        units: file.units,
        exclude: file.exclude,
        variants: file.variants,
        inputs,
    })
}

/// Whether a name can be a profile file name.
pub fn valid_profile_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
}

/// Writes a profile as `<dir>/<name>.toml`, creating the folder, and
/// returns the path.
pub fn write_profile(dir: &Path, profile: &Profile) -> Result<PathBuf, RepoError> {
    if !valid_profile_name(&profile.name) {
        return Err(RepoError::ProfileName(profile.name.clone()));
    }
    let file = ProfileFile {
        about: profile.about.clone(),
        extends: profile.extends.clone(),
        units: profile.units.clone(),
        exclude: profile.exclude.clone(),
        variants: profile.variants.clone(),
        inputs: profile
            .inputs
            .iter()
            .map(|(key, value)| {
                let value = match value {
                    InputValue::Text(text) => toml::Value::String(text.clone()),
                    InputValue::Flag(flag) => toml::Value::Boolean(*flag),
                };
                (key.clone(), value)
            })
            .collect(),
    };
    let path = dir.join(format!("{}.toml", profile.name));
    let text = toml::to_string(&file).map_err(|source| RepoError::TomlWrite {
        path: path.clone(),
        source,
    })?;
    fs::create_dir_all(dir).map_err(|source| RepoError::Io {
        path: dir.to_path_buf(),
        source,
    })?;
    fs::write(&path, text).map_err(|source| RepoError::Io {
        path: path.clone(),
        source,
    })?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_profile_is_written_and_read_back() {
        let dir = tempfile::tempdir().unwrap();
        let mut profile = Profile {
            name: "mine".into(),
            about: Some("Mine".into()),
            extends: Some("full".into()),
            exclude: vec!["discord".into()],
            ..Default::default()
        };
        profile.variants.insert("shell.zshrc".into(), "mine".into());
        profile
            .inputs
            .insert("git.name".into(), InputValue::Text("me".into()));
        profile
            .inputs
            .insert("ssh-key.fido".into(), InputValue::Flag(true));
        let path = write_profile(dir.path(), &profile).unwrap();
        assert_eq!(path.file_name().unwrap(), "mine.toml");
        let text = fs::read_to_string(&path).unwrap();
        assert!(text.contains("extends = \"full\""), "{text}");
        assert!(!text.contains("units"), "empty lists are left out: {text}");
        let profiles = read_profiles(dir.path()).unwrap();
        assert_eq!(profiles, vec![profile]);
    }

    #[test]
    fn names_and_inputs_are_checked() {
        let dir = tempfile::tempdir().unwrap();
        let bad = Profile {
            name: "Bad Name".into(),
            ..Default::default()
        };
        assert!(matches!(
            write_profile(dir.path(), &bad),
            Err(RepoError::ProfileName(_))
        ));
        fs::write(dir.path().join("p.toml"), "[inputs]\n\"git.name\" = 3\n").unwrap();
        assert!(matches!(
            read_profiles(dir.path()),
            Err(RepoError::ProfileInput { .. })
        ));
        assert!(
            read_profiles(&dir.path().join("nowhere"))
                .unwrap()
                .is_empty()
        );
    }
}
