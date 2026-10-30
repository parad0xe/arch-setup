//! The files of a unit: links to the repository or copies into the home
//! folder, with their permissions; system files copied with sudo. A file
//! already in place is left alone, a different one is kept as .bak.

use std::fs;
use std::io::Write;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use model::{FileEntry, Mode, Unit};
use thiserror::Error;

use crate::answers::{Answers, default_option};

#[derive(Debug, Error)]
#[error("{file}: {reason}")]
pub struct DeployError {
    pub file: String,
    pub reason: String,
}

/// Where the files go.
pub(crate) struct Target<'a> {
    pub home: &'a Path,
    pub sudo: &'a str,
    pub dry_run: bool,
    /// The repositories the files come from: nothing is deployed into them
    /// through a link.
    pub repositories: &'a [PathBuf],
}

/// The source of a file entry for the answers: `{id}` replaced by the
/// option of each variant of the unit, under the folder of the module
/// holding that option (the unit's, or a fragment's for an option it
/// added). An absolute source stays where it is.
pub(crate) fn resolve_source(unit: &Unit, source: &str, answers: &Answers) -> PathBuf {
    let mut resolved = source.to_string();
    let mut root = unit.root();
    for variant in unit.variants() {
        let placeholder = format!("{{{}}}", variant.id);
        if !resolved.contains(&placeholder) {
            continue;
        }
        let option = answers
            .variant(unit.id(), &variant.id)
            .unwrap_or(default_option(variant));
        if let Some(other) = unit.option_root(&variant.id, option) {
            root = other;
        }
        resolved = resolved.replace(&placeholder, option);
    }
    root.join(resolved)
}

/// Deploys one entry of a unit, logging what was done.
pub(crate) fn deploy(
    unit: &Unit,
    entry: &FileEntry,
    answers: &Answers,
    target: &Target,
    log: &mut dyn Write,
) -> Result<(), DeployError> {
    let source = resolve_source(unit, &entry.source, answers);
    let destination = if entry.is_system() {
        PathBuf::from(&entry.target)
    } else {
        target.home.join(&entry.target)
    };
    if entry.contents {
        deploy_contents(&source, &destination, entry, target, log)
    } else {
        deploy_one(&source, &destination, entry, target, log)
    }
}

/// Each entry of a folder of the repository goes into the target folder,
/// the hidden ones left out.
fn deploy_contents(
    source: &Path,
    destination: &Path,
    entry: &FileEntry,
    target: &Target,
    log: &mut dyn Write,
) -> Result<(), DeployError> {
    let linked = replace_link_by_folder(destination, target.dry_run, log)?;
    let mut children: Vec<PathBuf> = fs::read_dir(source)
        .map_err(|e| error(source, e))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| {
            !p.file_name()
                .is_some_and(|n| n.to_string_lossy().starts_with('.'))
        })
        .collect();
    children.sort();
    for child in children {
        let name = child.file_name().unwrap_or_default();
        let into = destination.join(name);
        if linked && target.dry_run {
            // The folder would be new: every entry would go in
            say(log, would(entry.mode, &child, &into));
            continue;
        }
        deploy_one(&child, &into, entry, target, log)?;
    }
    Ok(())
}

/// What a dry run says it would do.
fn would(mode: Mode, source: &Path, destination: &Path) -> String {
    match mode {
        Mode::Symlink => format!("would link {} -> {}", show(destination), show(source)),
        Mode::Copy => format!("would copy {} to {}", show(source), show(destination)),
    }
}

/// A folder deployed entry by entry must be a real folder: a link in its
/// place (the former setup linked the whole folder) is replaced, or its
/// entries would be taken for files to keep aside. Tells whether there was
/// a link.
fn replace_link_by_folder(
    destination: &Path,
    dry_run: bool,
    log: &mut dyn Write,
) -> Result<bool, DeployError> {
    if !destination
        .symlink_metadata()
        .is_ok_and(|m| m.file_type().is_symlink())
    {
        return Ok(false);
    }
    if dry_run {
        say(
            log,
            format!("would replace the link {} by a folder", show(destination)),
        );
        return Ok(true);
    }
    fs::remove_file(destination).map_err(|e| error(destination, e))?;
    fs::create_dir_all(destination).map_err(|e| error(destination, e))?;
    say(
        log,
        format!("replaced the link {} by a folder", show(destination)),
    );
    Ok(true)
}

/// An ancestor of the destination that is a link into one of the
/// repositories: writing under it would write into the repository.
fn link_into_repository(destination: &Path, repositories: &[PathBuf]) -> Option<PathBuf> {
    destination
        .ancestors()
        .skip(1)
        .find(|ancestor| {
            ancestor
                .symlink_metadata()
                .is_ok_and(|m| m.file_type().is_symlink())
                && fs::canonicalize(ancestor)
                    .is_ok_and(|real| repositories.iter().any(|repo| real.starts_with(repo)))
        })
        .map(Path::to_path_buf)
}

/// The destination is the source reached through a linked folder: keeping
/// it aside would move the source.
fn is_source_itself(source: &Path, destination: &Path) -> bool {
    !destination
        .symlink_metadata()
        .is_ok_and(|m| m.file_type().is_symlink())
        && matches!(
            (fs::canonicalize(source), fs::canonicalize(destination)),
            (Ok(a), Ok(b)) if a == b
        )
}

fn deploy_one(
    source: &Path,
    destination: &Path,
    entry: &FileEntry,
    target: &Target,
    log: &mut dyn Write,
) -> Result<(), DeployError> {
    if !source.exists() {
        return Err(DeployError {
            file: show(source),
            reason: "does not exist".to_string(),
        });
    }
    if is_source_itself(source, destination) {
        return Err(DeployError {
            file: show(destination),
            reason: "is the source itself (its folder is a link into the repository)".to_string(),
        });
    }
    if let Some(link) = link_into_repository(destination, target.repositories) {
        return Err(DeployError {
            file: show(destination),
            reason: format!(
                "would go into a repository through the link {}: deploy beside it, or extend the unit",
                show(&link)
            ),
        });
    }
    if entry.is_system() {
        return system_copy(source, destination, entry, target, log);
    }
    match entry.mode {
        Mode::Symlink => link(source, destination, entry.backup, target.dry_run, log),
        Mode::Copy => copy(source, destination, entry, target.dry_run, log),
    }
}

fn link(
    source: &Path,
    destination: &Path,
    backup: bool,
    dry_run: bool,
    log: &mut dyn Write,
) -> Result<(), DeployError> {
    if fs::read_link(destination).is_ok_and(|current| current == source) {
        say(
            log,
            format!("unchanged: {} -> {}", show(destination), show(source)),
        );
        return Ok(());
    }
    if dry_run {
        say(log, would(Mode::Symlink, source, destination));
        return Ok(());
    }
    set_aside(destination, backup, log)?;
    make_parent(destination)?;
    symlink(source, destination).map_err(|e| error(destination, e))?;
    say(
        log,
        format!("linked {} -> {}", show(destination), show(source)),
    );
    Ok(())
}

fn copy(
    source: &Path,
    destination: &Path,
    entry: &FileEntry,
    dry_run: bool,
    log: &mut dyn Write,
) -> Result<(), DeployError> {
    if destination
        .symlink_metadata()
        .is_ok_and(|m| !m.file_type().is_symlink())
        && identical(source, destination)?
    {
        if let Some(mode) = entry.permissions {
            set_permissions(destination, mode)?;
        }
        say(log, format!("unchanged: {}", show(destination)));
        return Ok(());
    }
    if dry_run {
        say(log, would(Mode::Copy, source, destination));
        return Ok(());
    }
    set_aside(destination, entry.backup, log)?;
    make_parent(destination)?;
    copy_recursive(source, destination)?;
    if let Some(mode) = entry.permissions {
        set_permissions(destination, mode)?;
    }
    say(
        log,
        format!("copied {} to {}", show(source), show(destination)),
    );
    Ok(())
}

/// A system file: compared, kept aside and installed with sudo, owned by
/// root, with the permissions of the entry.
fn system_copy(
    source: &Path,
    destination: &Path,
    entry: &FileEntry,
    target: &Target,
    log: &mut dyn Write,
) -> Result<(), DeployError> {
    if source.is_dir() {
        return Err(DeployError {
            file: show(source),
            reason: "a system file is a file, not a folder".to_string(),
        });
    }
    let mode = format!("{:o}", entry.permissions.unwrap_or(0o644));
    if sudo(
        target.sudo,
        &["cmp", "-s", &show(source), &show(destination)],
    ) {
        say(log, format!("unchanged: {}", show(destination)));
        return Ok(());
    }
    if target.dry_run {
        say(
            log,
            format!(
                "would install {} as {} ({mode}, root)",
                show(source),
                show(destination)
            ),
        );
        return Ok(());
    }
    if sudo(target.sudo, &["test", "-e", &show(destination)]) {
        if entry.backup {
            let aside = free_name(destination, |p| {
                sudo(target.sudo, &["test", "-e", &show(p)])
            });
            if !sudo(target.sudo, &["mv", &show(destination), &show(&aside)]) {
                return Err(DeployError {
                    file: show(destination),
                    reason: "could not be kept aside".to_string(),
                });
            }
            say(
                log,
                format!(
                    "kept the existing {} as {}",
                    show(destination),
                    show(&aside)
                ),
            );
        } else if !sudo(target.sudo, &["rm", "-rf", &show(destination)]) {
            return Err(DeployError {
                file: show(destination),
                reason: "could not be replaced".to_string(),
            });
        }
    }
    if !sudo(
        target.sudo,
        &[
            "install",
            "-D",
            "-m",
            &mode,
            "-o",
            "root",
            "-g",
            "root",
            &show(source),
            &show(destination),
        ],
    ) {
        return Err(DeployError {
            file: show(destination),
            reason: "could not be installed with sudo".to_string(),
        });
    }
    say(
        log,
        format!(
            "installed {} as {} ({mode}, root)",
            show(source),
            show(destination)
        ),
    );
    Ok(())
}

/// Moves an existing file or folder out of the way: to a free .bak name,
/// or removed without backup.
fn set_aside(destination: &Path, backup: bool, log: &mut dyn Write) -> Result<(), DeployError> {
    let Ok(metadata) = destination.symlink_metadata() else {
        return Ok(());
    };
    if backup {
        let aside = free_name(destination, |p| p.symlink_metadata().is_ok());
        fs::rename(destination, &aside).map_err(|e| error(destination, e))?;
        say(
            log,
            format!(
                "kept the existing {} as {}",
                show(destination),
                show(&aside)
            ),
        );
    } else if metadata.is_dir() {
        fs::remove_dir_all(destination).map_err(|e| error(destination, e))?;
    } else {
        fs::remove_file(destination).map_err(|e| error(destination, e))?;
    }
    Ok(())
}

/// `<path>.bak`, or `.bak.1`, `.bak.2`... when taken.
fn free_name(path: &Path, taken: impl Fn(&Path) -> bool) -> PathBuf {
    let base = format!("{}.bak", path.display());
    let mut candidate = PathBuf::from(&base);
    let mut n = 1;
    while taken(&candidate) {
        candidate = PathBuf::from(format!("{base}.{n}"));
        n += 1;
    }
    candidate
}

/// Two files with the same bytes, or two folders with the same entries,
/// identical.
fn identical(a: &Path, b: &Path) -> Result<bool, DeployError> {
    match (a.is_dir(), b.is_dir()) {
        (true, true) => {
            let names = |dir: &Path| -> Result<Vec<String>, DeployError> {
                let mut names: Vec<String> = fs::read_dir(dir)
                    .map_err(|e| error(dir, e))?
                    .filter_map(|e| e.ok().map(|e| e.file_name().to_string_lossy().into_owned()))
                    .collect();
                names.sort();
                Ok(names)
            };
            let (left, right) = (names(a)?, names(b)?);
            if left != right {
                return Ok(false);
            }
            for name in left {
                if !identical(&a.join(&name), &b.join(&name))? {
                    return Ok(false);
                }
            }
            Ok(true)
        }
        (false, false) => {
            Ok(fs::read(a).map_err(|e| error(a, e))? == fs::read(b).map_err(|e| error(b, e))?)
        }
        _ => Ok(false),
    }
}

fn copy_recursive(source: &Path, destination: &Path) -> Result<(), DeployError> {
    if source.is_dir() {
        fs::create_dir_all(destination).map_err(|e| error(destination, e))?;
        for entry in fs::read_dir(source).map_err(|e| error(source, e))? {
            let entry = entry.map_err(|e| error(source, e))?;
            copy_recursive(&entry.path(), &destination.join(entry.file_name()))?;
        }
        Ok(())
    } else {
        fs::copy(source, destination).map_err(|e| error(destination, e))?;
        Ok(())
    }
}

/// Sets the permissions of a file, or of every file of a folder.
fn set_permissions(path: &Path, mode: u32) -> Result<(), DeployError> {
    if path.is_dir() {
        for entry in fs::read_dir(path).map_err(|e| error(path, e))? {
            let entry = entry.map_err(|e| error(path, e))?;
            set_permissions(&entry.path(), mode)?;
        }
        Ok(())
    } else {
        fs::set_permissions(path, fs::Permissions::from_mode(mode)).map_err(|e| error(path, e))
    }
}

fn make_parent(destination: &Path) -> Result<(), DeployError> {
    match destination.parent() {
        Some(parent) => fs::create_dir_all(parent).map_err(|e| error(parent, e)),
        None => Ok(()),
    }
}

fn sudo(program: &str, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn say(log: &mut dyn Write, text: String) {
    let _ = writeln!(log, "{text}");
}

fn show(path: &Path) -> String {
    path.display().to_string()
}

fn error(path: &Path, source: std::io::Error) -> DeployError {
    DeployError {
        file: show(path),
        reason: source.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(source: &str, target: &str, mode: Mode) -> FileEntry {
        FileEntry {
            source: source.into(),
            target: target.into(),
            mode,
            contents: false,
            backup: true,
            permissions: None,
        }
    }

    #[test]
    fn a_folder_linked_as_a_whole_becomes_a_folder_of_links() {
        let repo = tempfile::tempdir().unwrap();
        let home = tempfile::tempdir().unwrap();
        let source = repo.path().join("hypr");
        fs::create_dir_all(source.join("conf")).unwrap();
        fs::write(source.join("hyprland.lua"), "lua").unwrap();
        fs::write(source.join(".hidden"), "").unwrap();
        let destination = home.path().join(".config/hypr");
        fs::create_dir_all(home.path().join(".config")).unwrap();
        symlink(&source, &destination).unwrap();
        let mut entry = entry("hypr", ".config/hypr", Mode::Symlink);
        entry.contents = true;
        let mut log = Vec::new();

        let dry = Target {
            home: home.path(),
            sudo: "false",
            dry_run: true,
            repositories: &[],
        };
        deploy_contents(&source, &destination, &entry, &dry, &mut log).unwrap();
        assert!(
            destination
                .symlink_metadata()
                .unwrap()
                .file_type()
                .is_symlink()
        );
        let text = String::from_utf8(log.clone()).unwrap();
        assert!(text.contains("would replace the link"), "{text}");
        assert!(
            text.contains("would link") && text.contains("hyprland.lua"),
            "{text}"
        );
        assert!(source.join("conf").is_dir(), "a dry run moves nothing");

        let real = Target {
            dry_run: false,
            ..dry
        };
        deploy_contents(&source, &destination, &entry, &real, &mut log).unwrap();
        assert!(destination.symlink_metadata().unwrap().is_dir());
        assert_eq!(
            fs::read_link(destination.join("conf")).unwrap(),
            source.join("conf")
        );
        assert_eq!(
            fs::read_link(destination.join("hyprland.lua")).unwrap(),
            source.join("hyprland.lua")
        );
        assert!(!destination.join(".hidden").exists());
        assert!(
            source.join("conf").is_dir() && source.join("hyprland.lua").is_file(),
            "the repository is untouched"
        );
        assert!(!source.join("conf.bak").exists());
        let text = String::from_utf8(log).unwrap();
        assert!(text.contains("replaced the link"), "{text}");
    }

    #[test]
    fn a_destination_that_is_the_source_is_refused() {
        let repo = tempfile::tempdir().unwrap();
        let home = tempfile::tempdir().unwrap();
        let source = repo.path().join("hypr");
        fs::create_dir_all(source.join("conf")).unwrap();
        fs::create_dir_all(home.path().join(".config")).unwrap();
        symlink(&source, home.path().join(".config/hypr")).unwrap();
        let t = Target {
            home: home.path(),
            sudo: "false",
            dry_run: false,
            repositories: &[],
        };
        let mut log = Vec::new();
        let error = deploy_one(
            &source.join("conf"),
            &home.path().join(".config/hypr/conf"),
            &entry("hypr/conf", ".config/hypr/conf", Mode::Symlink),
            &t,
            &mut log,
        )
        .unwrap_err();
        assert!(error.reason.contains("is the source itself"), "{error}");
        assert!(source.join("conf").is_dir() && !source.join("conf.bak").exists());
    }

    #[test]
    fn a_destination_under_a_link_into_a_repository_is_refused() {
        let repo = tempfile::tempdir().unwrap();
        let home = tempfile::tempdir().unwrap();
        let module = repo.path().join("modules/m");
        fs::create_dir_all(module.join("files/hypr")).unwrap();
        fs::write(module.join("files/local.lua"), "").unwrap();
        fs::create_dir_all(home.path().join(".config")).unwrap();
        symlink(module.join("files/hypr"), home.path().join(".config/hypr")).unwrap();
        let repositories = [fs::canonicalize(repo.path()).unwrap()];
        let t = Target {
            home: home.path(),
            sudo: "false",
            dry_run: false,
            repositories: &repositories,
        };
        let mut log = Vec::new();
        let error = deploy_one(
            &module.join("files/local.lua"),
            &home.path().join(".config/hypr/local.lua"),
            &entry("files/local.lua", ".config/hypr/local.lua", Mode::Copy),
            &t,
            &mut log,
        )
        .unwrap_err();
        assert!(error.reason.contains("through the link"), "{error}");
        assert!(!module.join("files/hypr/local.lua").exists());
    }

    #[test]
    fn links_once_and_keeps_a_different_file_aside() {
        let repo = tempfile::tempdir().unwrap();
        let home = tempfile::tempdir().unwrap();
        fs::write(repo.path().join("conf"), "new").unwrap();
        fs::write(home.path().join(".conf"), "old").unwrap();
        let mut log = Vec::new();
        let t = Target {
            home: home.path(),
            sudo: "false",
            dry_run: false,
            repositories: &[],
        };
        link(
            &repo.path().join("conf"),
            &home.path().join(".conf"),
            true,
            false,
            &mut log,
        )
        .unwrap();
        assert_eq!(
            fs::read_link(home.path().join(".conf")).unwrap(),
            repo.path().join("conf")
        );
        assert_eq!(
            fs::read_to_string(home.path().join(".conf.bak")).unwrap(),
            "old"
        );
        link(
            &repo.path().join("conf"),
            &home.path().join(".conf"),
            true,
            false,
            &mut log,
        )
        .unwrap();
        let text = String::from_utf8(log).unwrap();
        assert!(
            text.contains("kept the existing")
                && text.contains("linked")
                && text.contains("unchanged"),
            "{text}"
        );
        let _ = t;
    }

    #[test]
    fn copies_with_permissions_and_detects_identical_folders() {
        let repo = tempfile::tempdir().unwrap();
        let home = tempfile::tempdir().unwrap();
        fs::create_dir_all(repo.path().join("bin")).unwrap();
        fs::write(repo.path().join("bin/tool"), "#!/bin/sh\n").unwrap();
        let mut e = entry("bin", ".local/bin", Mode::Copy);
        e.permissions = Some(0o755);
        let mut log = Vec::new();
        copy(
            &repo.path().join("bin"),
            &home.path().join(".local/bin"),
            &e,
            false,
            &mut log,
        )
        .unwrap();
        let mode = fs::metadata(home.path().join(".local/bin/tool"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o755);
        copy(
            &repo.path().join("bin"),
            &home.path().join(".local/bin"),
            &e,
            false,
            &mut log,
        )
        .unwrap();
        let text = String::from_utf8(log).unwrap();
        assert_eq!(text.matches("copied").count(), 1, "{text}");
        assert!(text.contains("unchanged"), "{text}");
        assert!(!home.path().join(".local/bin.bak").exists());
    }

    #[test]
    fn a_dry_run_changes_nothing_and_backup_false_replaces() {
        let repo = tempfile::tempdir().unwrap();
        let home = tempfile::tempdir().unwrap();
        fs::write(repo.path().join("rc"), "new").unwrap();
        fs::write(home.path().join(".rc"), "old").unwrap();
        let mut log = Vec::new();
        link(
            &repo.path().join("rc"),
            &home.path().join(".rc"),
            true,
            true,
            &mut log,
        )
        .unwrap();
        assert_eq!(fs::read_to_string(home.path().join(".rc")).unwrap(), "old");
        assert!(String::from_utf8(log).unwrap().contains("would link"));
        let mut log = Vec::new();
        link(
            &repo.path().join("rc"),
            &home.path().join(".rc"),
            false,
            false,
            &mut log,
        )
        .unwrap();
        assert!(!home.path().join(".rc.bak").exists(), "no backup asked");
        assert!(home.path().join(".rc").is_symlink());
    }

    #[test]
    fn backup_names_are_free_names() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("x");
        fs::write(&file, "").unwrap();
        fs::write(dir.path().join("x.bak"), "").unwrap();
        assert_eq!(free_name(&file, |p| p.exists()), dir.path().join("x.bak.1"));
    }
}
