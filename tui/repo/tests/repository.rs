//! The repository of this checkout: its manifests load into a registry and
//! its profiles resolve.

use std::path::PathBuf;

use model::{Platform, Profiles, Registry};
use repo::Repository;

fn checkout() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn arch_desktop() -> Platform {
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
fn the_manifests_of_the_repository_load() {
    let repo = Repository::open(checkout()).unwrap();
    let registry = Registry::new(repo.declarations().unwrap(), &arch_desktop()).unwrap();
    assert!(registry.modules().len() >= 10);
    assert!(registry.units().count() >= 40);
    let desktop = registry.unit("desktop").expect("the desktop unit");
    assert!(desktop.offered());
    assert!(
        !registry.unit("hypr-tools").unwrap().offered(),
        "required parts come with their parent"
    );
    assert!(
        registry.unit("sddm").unwrap().offered(),
        "optional parts are offered"
    );
    assert!(registry.unit("nvidia").unwrap().available());
    assert!(!registry.unit("vm-guest").unwrap().available());
    assert!(registry.unit("system").unwrap().always());

    let profiles = Profiles::new(repo.profiles().unwrap()).unwrap();
    for name in profiles.names() {
        let resolved = profiles
            .resolve(name, &registry)
            .unwrap_or_else(|e| panic!("profile {name}: {e}"));
        assert!(
            resolved.warnings.is_empty(),
            "profile {name}: {:?}",
            resolved.warnings
        );
    }
    let full = profiles.resolve("full", &registry).unwrap();
    assert_eq!(
        full.selection.units().count(),
        registry.units().filter(|u| u.offered()).count()
    );
    let plan = model::plan::build(&registry, &full.selection);
    assert_eq!(plan.steps()[0].unit(), "system");
    assert!(plan.left_out().is_empty());
}

#[test]
fn on_arm_the_x86_only_units_are_unavailable() {
    let repo = Repository::open(checkout()).unwrap();
    let platform = Platform {
        arch: "aarch64".into(),
        cpu: "apple".into(),
        apple_silicon: true,
        gpu: vec![],
        ..arch_desktop()
    };
    let registry = Registry::new(repo.declarations().unwrap(), &platform).unwrap();
    assert!(!registry.unit("microcode").unwrap().available());
    assert!(!registry.unit("discord").unwrap().available());
    assert!(!registry.unit("dualboot").unwrap().available());
    assert!(
        registry.unit("ghostty").unwrap().packages().is_empty(),
        "ghostty is built, not installed, on ARM"
    );
    assert_eq!(
        registry
            .unit("ghostty")
            .unwrap()
            .hooks()
            .collect::<Vec<_>>(),
        ["build_ghostty"]
    );
    assert!(
        registry
            .unit("desktop-tools")
            .unwrap()
            .packages()
            .iter()
            .all(|p| p != "rofi")
    );
}
