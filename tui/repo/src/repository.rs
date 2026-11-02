//! A setup repository on disk.

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use model::{Declarations, FileEntry, ModuleDeclaration, Profile, Variant};

use crate::error::RepoError;
use crate::manifest;
use crate::profiles;

/// The repository: one folder per module under `modules/`, holding its
/// `module.toml`, its `hooks.sh` and the files its units deploy (`files/`);
/// `profiles/*.toml`. The public one also holds `lib/hook.sh`; a private
/// one, read after it, adds its own modules and profiles.
#[derive(Debug, Clone)]
pub struct Repository {
    root: PathBuf,
}

impl Repository {
    /// Opens the repository at a path, made absolute.
    pub fn open(root: impl AsRef<Path>) -> Result<Repository, RepoError> {
        let given = root.as_ref();
        let root = fs::canonicalize(given).map_err(|source| RepoError::NotARepository {
            path: given.to_path_buf(),
            reason: source.to_string(),
        })?;
        if !root.join("modules").is_dir() {
            return Err(RepoError::NotARepository {
                path: root,
                reason: "no modules folder".to_string(),
            });
        }
        Ok(Repository { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// The script running one hook.
    pub fn hook_script(&self) -> PathBuf {
        self.root.join("lib/hook.sh")
    }

    /// The folder of a module: its manifest, its hooks and its files.
    pub fn module_dir(&self, module: &str) -> PathBuf {
        self.root.join("modules").join(module)
    }

    /// The script holding the hooks of a module.
    pub fn module_script(&self, module: &str) -> PathBuf {
        self.module_dir(module).join("hooks.sh")
    }

    /// Reads every module, in folder name order, and checks that the files
    /// the units deploy exist and that their hooks are functions of the
    /// module's script.
    pub fn declarations(&self) -> Result<Declarations, RepoError> {
        let mut folders = read_dir(&self.root.join("modules"))?;
        folders.sort();
        let mut modules = Vec::new();
        for folder in folders {
            let name = folder
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or_default()
                .to_string();
            if name.starts_with('.') {
                continue;
            }
            let path = folder.join("module.toml");
            if !folder.is_dir() || !path.is_file() {
                return Err(RepoError::ModuleLayout { path: folder });
            }
            if !manifest::valid_module_id(&name) {
                return Err(RepoError::ModuleId { path: folder, name });
            }
            let text = read(&path)?;
            let module = manifest::parse(&path, &folder, &name, &text)?;
            self.check_module(&module)?;
            modules.push(module);
        }
        check_added_options(&modules)?;
        Ok(Declarations { modules })
    }

    /// The profiles of the repository.
    pub fn profiles(&self) -> Result<Vec<Profile>, RepoError> {
        profiles::read_profiles(&self.root.join("profiles"))
    }

    /// The declarations of several repositories, in order (the public one
    /// first, then a private one). A module declared twice names both.
    pub fn load(repositories: &[Repository]) -> Result<Declarations, RepoError> {
        let mut modules: Vec<ModuleDeclaration> = Vec::new();
        for repository in repositories {
            for module in repository.declarations()?.modules {
                if let Some(first) = modules.iter().find(|m| m.id == module.id) {
                    return Err(RepoError::DuplicateModule {
                        id: module.id,
                        first: first.root.clone(),
                        second: module.root,
                    });
                }
                modules.push(module);
            }
        }
        check_added_options(&modules)?;
        Ok(Declarations { modules })
    }

    fn check_module(&self, module: &ModuleDeclaration) -> Result<(), RepoError> {
        let script = self.module_script(&module.id);
        let functions = if script.is_file() {
            Some(functions_of(&read(&script)?))
        } else {
            None
        };
        let check_hooks = |unit: &str, hooks: &[model::Hook]| -> Result<(), RepoError> {
            for hook in hooks {
                let Some(functions) = &functions else {
                    return Err(RepoError::ScriptMissing {
                        unit: unit.to_string(),
                        script: script.clone(),
                    });
                };
                if !functions.contains(&hook.run) {
                    return Err(RepoError::HookUndefined {
                        unit: unit.to_string(),
                        function: hook.run.clone(),
                        script: script.clone(),
                    });
                }
            }
            Ok(())
        };
        for unit in &module.units {
            for file in &unit.files {
                check_sources(&module.root, &unit.id, &unit.variants, file)?;
            }
            check_hooks(&unit.id, &unit.hooks)?;
        }
        for fragment in &module.fragments {
            for file in &fragment.files {
                check_sources(&module.root, &fragment.unit, &fragment.variants, file)?;
            }
            check_hooks(&fragment.unit, &fragment.hooks)?;
        }
        Ok(())
    }
}

/// Every version of a source (one per combination of the variants it
/// names) exists in the module's folder; a folder when its contents are
/// deployed.
fn check_sources(
    root: &Path,
    unit: &str,
    variants: &[Variant],
    file: &FileEntry,
) -> Result<(), RepoError> {
    for source in expand(&file.source, variants) {
        let path = root.join(&source);
        if !path.exists() {
            return Err(RepoError::MissingSource {
                unit: unit.to_string(),
                file: source,
            });
        }
        if file.contents && !path.is_dir() {
            return Err(RepoError::ContentsOnFile {
                unit: unit.to_string(),
                file: source,
            });
        }
    }
    Ok(())
}

/// The options a fragment adds to a variant of a unit of an earlier module
/// have their files in the fragment's module, at the path the unit's files
/// name: every such file exists.
fn check_added_options(modules: &[ModuleDeclaration]) -> Result<(), RepoError> {
    for (m, module) in modules.iter().enumerate() {
        for fragment in &module.fragments {
            let Some(unit) = modules[..m]
                .iter()
                .flat_map(|other| &other.units)
                .find(|u| u.id == fragment.unit)
            else {
                continue;
            };
            for added in &fragment.variants {
                if !unit.variants.iter().any(|v| v.id == added.id) {
                    continue;
                }
                // The unit's variants, this one reduced to the new options
                let variants: Vec<Variant> = unit
                    .variants
                    .iter()
                    .map(|v| {
                        if v.id == added.id {
                            Variant {
                                options: added.options.clone(),
                                ..v.clone()
                            }
                        } else {
                            v.clone()
                        }
                    })
                    .collect();
                let placeholder = format!("{{{}}}", added.id);
                for file in unit
                    .files
                    .iter()
                    .filter(|f| f.source.contains(&placeholder))
                {
                    for source in expand(&file.source, &variants) {
                        if !module.root.join(&source).exists() {
                            return Err(RepoError::MissingSource {
                                unit: fragment.unit.clone(),
                                file: source,
                            });
                        }
                    }
                }
            }
        }
    }
    Ok(())
}

/// The source with every combination of the variants' options.
fn expand(source: &str, variants: &[Variant]) -> Vec<String> {
    let mut sources = vec![source.to_string()];
    for variant in variants {
        let placeholder = format!("{{{}}}", variant.id);
        let placeholder = placeholder.as_str();
        if !source.contains(placeholder) {
            continue;
        }
        sources = sources
            .iter()
            .flat_map(|s| {
                variant
                    .options
                    .iter()
                    .map(move |o| s.replace(placeholder, o))
            })
            .collect();
    }
    sources
}

/// The functions a bash script defines: its `name() {` lines.
fn functions_of(script: &str) -> BTreeSet<String> {
    script
        .lines()
        .filter_map(|line| line.strip_suffix("() {"))
        .filter(|name| {
            let mut chars = name.chars();
            chars
                .next()
                .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
                && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
        })
        .map(str::to_string)
        .collect()
}

pub(crate) fn read(path: &Path) -> Result<String, RepoError> {
    fs::read_to_string(path).map_err(|source| RepoError::Io {
        path: path.to_path_buf(),
        source,
    })
}

pub(crate) fn read_dir(dir: &Path) -> Result<Vec<PathBuf>, RepoError> {
    let entries = fs::read_dir(dir).map_err(|source| RepoError::Io {
        path: dir.to_path_buf(),
        source,
    })?;
    entries
        .map(|entry| {
            entry.map(|e| e.path()).map_err(|source| RepoError::Io {
                path: dir.to_path_buf(),
                source,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use model::UnitDeclaration;

    #[test]
    fn sources_expand_over_the_variants() {
        let unit = UnitDeclaration {
            variants: vec![
                model::Variant {
                    id: "a".into(),
                    name: "A".into(),
                    options: vec!["1".into(), "2".into()],
                    default: None,
                },
                model::Variant {
                    id: "b".into(),
                    name: "B".into(),
                    options: vec!["x".into(), "y".into()],
                    default: None,
                },
            ],
            ..Default::default()
        };
        assert_eq!(
            expand("p/{a}/{b}", &unit.variants),
            ["p/1/x", "p/1/y", "p/2/x", "p/2/y"]
        );
        assert_eq!(expand("p/{a}", &unit.variants), ["p/1", "p/2"]);
        assert_eq!(expand("plain", &unit.variants), ["plain"]);
    }

    #[test]
    fn functions_are_the_name_brace_lines() {
        let script = "#!/bin/bash\nsetup_x() {\n    :\n}\n_helper() {\n}\nnot_a_fn () {\n";
        let functions = functions_of(script);
        assert!(functions.contains("setup_x") && functions.contains("_helper"));
        assert_eq!(functions.len(), 2);
    }

    #[test]
    fn a_repository_is_checked_against_its_files() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        let module = root.join("modules/demo");
        fs::create_dir_all(module.join("files/x/dark")).unwrap();
        fs::write(module.join("hooks.sh"), "setup_x() {\n    :\n}\n").unwrap();
        let manifest = |files: &str, hooks: &str| {
            fs::write(
                module.join("module.toml"),
                format!("[module]\nname = \"Demo\"\n\n[[unit]]\nid = \"x\"\nname = \"X\"\n{files}\n{hooks}\n"),
            )
            .unwrap();
        };
        let repo = Repository::open(root).unwrap();
        assert!(
            Repository::open(root.join("modules")).is_err(),
            "a folder without modules/ is no repository"
        );

        manifest(
            "files = [{ source = \"files/x/{theme}\", target = \".config/x\" }]\nvariants = [{ id = \"theme\", name = \"T\", options = [\"dark\", \"light\"] }]",
            "hooks = [\"setup_x\"]",
        );
        let error = repo.declarations().unwrap_err();
        assert!(
            matches!(&error, RepoError::MissingSource { unit, file } if unit == "x" && file == "files/x/light"),
            "{error}"
        );

        fs::create_dir_all(module.join("files/x/light")).unwrap();
        assert_eq!(
            repo.declarations().unwrap().modules[0].units[0].hooks[0].run,
            "setup_x"
        );

        manifest(
            "files = [{ source = \"files/x/dark\", target = \".config/x\" }]",
            "hooks = [\"missing\"]",
        );
        let error = repo.declarations().unwrap_err();
        assert!(
            matches!(&error, RepoError::HookUndefined { function, .. } if function == "missing"),
            "{error}"
        );

        fs::write(module.join("files/x/dark/file"), "").unwrap();
        manifest(
            "files = [{ source = \"files/x/dark/file\", target = \".config/x\", contents = true }]",
            "",
        );
        let error = repo.declarations().unwrap_err();
        assert!(
            matches!(&error, RepoError::ContentsOnFile { .. }),
            "{error}"
        );

        // A manifest left at the old place is a layout mistake, not a module
        manifest(
            "files = [{ source = \"files/x/dark\", target = \".config/x\" }]",
            "hooks = [\"setup_x\"]",
        );
        fs::write(root.join("modules/old.toml"), "[module]\nname = \"Old\"\n").unwrap();
        let error = repo.declarations().unwrap_err();
        assert!(matches!(&error, RepoError::ModuleLayout { .. }), "{error}");
    }

    #[test]
    fn the_files_of_the_options_a_fragment_adds_are_checked_in_its_module() {
        let public = tempfile::tempdir().unwrap();
        let private = tempfile::tempdir().unwrap();
        let desktop = public.path().join("modules/desktop");
        fs::create_dir_all(desktop.join("files/k")).unwrap();
        fs::write(desktop.join("files/k/default.lua"), "").unwrap();
        fs::write(
            desktop.join("module.toml"),
            "[module]\nname = \"D\"\n\n[[unit]]\nid = \"desktop\"\nname = \"Desktop\"\nfiles = [{ source = \"files/k/{keybinds}.lua\", target = \".k.lua\" }]\nvariants = [{ id = \"keybinds\", name = \"Keys\", options = [\"default\"] }]\n",
        )
        .unwrap();
        let work = private.path().join("modules/work");
        fs::create_dir_all(work.join("files/k")).unwrap();
        fs::write(
            work.join("module.toml"),
            "[module]\nname = \"W\"\n\n[[unit]]\nextend = \"desktop\"\nvariants = [{ id = \"keybinds\", options = [\"work\"] }]\n",
        )
        .unwrap();
        let repos = [
            Repository::open(public.path()).unwrap(),
            Repository::open(private.path()).unwrap(),
        ];
        let error = Repository::load(&repos).unwrap_err();
        assert!(
            matches!(&error, RepoError::MissingSource { unit, file } if unit == "desktop" && file == "files/k/work.lua"),
            "{error}"
        );
        fs::write(work.join("files/k/work.lua"), "").unwrap();
        let declarations = Repository::load(&repos).unwrap();
        assert_eq!(
            declarations.modules[1].fragments[0].variants[0].options,
            ["work"]
        );
    }

    #[test]
    fn several_repositories_add_up_and_refuse_a_module_twice() {
        let public = tempfile::tempdir().unwrap();
        let private = tempfile::tempdir().unwrap();
        for (dir, module) in [(&public, "alpha"), (&private, "mounts")] {
            fs::create_dir_all(dir.path().join(format!("modules/{module}"))).unwrap();
            fs::write(
                dir.path().join(format!("modules/{module}/module.toml")),
                format!("[module]\nname = \"{module}\"\n\n[[unit]]\nid = \"{module}-unit\"\nname = \"U\"\npackages = [\"p\"]\n"),
            )
            .unwrap();
        }
        let repos = [
            Repository::open(public.path()).unwrap(),
            Repository::open(private.path()).unwrap(),
        ];
        let declarations = Repository::load(&repos).unwrap();
        assert_eq!(declarations.modules.len(), 2);
        assert_eq!(
            declarations.modules[1].root,
            fs::canonicalize(private.path())
                .unwrap()
                .join("modules/mounts")
        );

        fs::create_dir_all(private.path().join("modules/alpha")).unwrap();
        fs::write(
            private.path().join("modules/alpha/module.toml"),
            "[module]\nname = \"Alpha again\"\n",
        )
        .unwrap();
        let error = Repository::load(&repos).unwrap_err();
        assert!(
            matches!(&error, RepoError::DuplicateModule { id, .. } if id == "alpha"),
            "{error}"
        );
    }
}
