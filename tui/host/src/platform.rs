//! The platform the manifests test, read from the machine.

use std::fs;
use std::path::Path;

use model::Platform;

use crate::probe::{installed, output, read};

/// Reads the platform of this machine.
pub fn probe_platform() -> Platform {
    let compatible = read("/proc/device-tree/compatible").unwrap_or_default();
    let apple_silicon = is_apple_silicon(&compatible);
    Platform {
        distro: distro(&read("/etc/os-release").unwrap_or_default()),
        arch: std::env::consts::ARCH.to_string(),
        cpu: cpu(&read("/proc/cpuinfo").unwrap_or_default(), apple_silicon),
        gpu: gpu_vendors(&pci_display_vendors(Path::new("/sys/bus/pci/devices"))),
        vm: crate::probe::succeeds("systemd-detect-virt", &["--vm", "--quiet"]),
        apple_silicon,
        bootloader: bootloader(
            Path::new("/etc/default/grub"),
            Path::new("/boot/loader/entries"),
            installed("grub-mkconfig"),
        ),
        filesystems: filesystems(&output("lsblk", &["-nro", "FSTYPE"]).unwrap_or_default()),
    }
}

/// The distribution of an os-release file: `arch` for Arch Linux and Arch
/// Linux ARM, else its ID.
pub(crate) fn distro(os_release: &str) -> String {
    let id = os_release
        .lines()
        .find_map(|line| line.strip_prefix("ID="))
        .map(|value| value.trim().trim_matches('"').to_string())
        .unwrap_or_default();
    match id.as_str() {
        "arch" | "archarm" => "arch".to_string(),
        other => other.to_string(),
    }
}

/// The CPU vendor of a cpuinfo file: `intel`, `amd`, `apple` on Apple
/// Silicon, `other`.
pub(crate) fn cpu(cpuinfo: &str, apple_silicon: bool) -> String {
    if apple_silicon {
        return "apple".to_string();
    }
    let vendor = cpuinfo
        .lines()
        .find_map(|line| line.strip_prefix("vendor_id"))
        .and_then(|rest| rest.split_once(':'))
        .map(|(_, value)| value.trim());
    match vendor {
        Some("GenuineIntel") => "intel",
        Some("AuthenticAMD") => "amd",
        _ => "other",
    }
    .to_string()
}

pub(crate) fn is_apple_silicon(compatible: &str) -> bool {
    compatible.contains("apple,arm-platform")
}

/// The vendor ids of the PCI display controllers (class 0x03).
fn pci_display_vendors(devices: &Path) -> Vec<String> {
    let Ok(entries) = fs::read_dir(devices) else {
        return Vec::new();
    };
    entries
        .filter_map(|entry| entry.ok().map(|e| e.path()))
        .filter(|device| read(device.join("class")).is_some_and(|class| class.starts_with("0x03")))
        .filter_map(|device| read(device.join("vendor")))
        .collect()
}

/// The GPU vendors of PCI vendor ids: `nvidia`, `amd`, `intel`.
pub(crate) fn gpu_vendors(vendor_ids: &[String]) -> Vec<String> {
    let mut vendors: Vec<String> = vendor_ids
        .iter()
        .filter_map(|id| match id.to_lowercase().as_str() {
            "0x10de" => Some("nvidia"),
            "0x1002" | "0x1022" => Some("amd"),
            "0x8086" => Some("intel"),
            _ => None,
        })
        .map(str::to_string)
        .collect();
    vendors.sort();
    vendors.dedup();
    vendors
}

/// `grub` with its default file and grub-mkconfig, `systemd-boot` with its
/// entries folder, else `none`.
pub(crate) fn bootloader(
    grub_default: &Path,
    loader_entries: &Path,
    grub_mkconfig: bool,
) -> String {
    if grub_default.is_file() && grub_mkconfig {
        "grub"
    } else if loader_entries.is_dir() {
        "systemd-boot"
    } else {
        "none"
    }
    .to_string()
}

/// The file system types of an `lsblk -nro FSTYPE` output, sorted, once
/// each.
pub(crate) fn filesystems(lsblk: &str) -> Vec<String> {
    let mut types: Vec<String> = lsblk
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect();
    types.sort();
    types.dedup();
    types
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distro_comes_from_the_os_release_id() {
        assert_eq!(distro("NAME=\"Arch Linux\"\nID=arch\n"), "arch");
        assert_eq!(distro("ID=\"archarm\"\n"), "arch");
        assert_eq!(distro("ID=ubuntu\nID_LIKE=debian\n"), "ubuntu");
        assert_eq!(distro(""), "");
    }

    #[test]
    fn cpu_vendor_is_read_or_apple() {
        assert_eq!(
            cpu("processor\t: 0\nvendor_id\t: GenuineIntel\n", false),
            "intel"
        );
        assert_eq!(cpu("vendor_id\t: AuthenticAMD\n", false), "amd");
        assert_eq!(cpu("processor\t: 0\n", false), "other");
        assert_eq!(cpu("", true), "apple");
        assert!(is_apple_silicon(
            "apple,j314s\0apple,t6000\0apple,arm-platform\0"
        ));
    }

    #[test]
    fn gpu_vendors_from_pci_ids() {
        let ids: Vec<String> = ["0x10de", "0x8086", "0x10de", "0x1234"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(gpu_vendors(&ids), ["intel", "nvidia"]);
        assert!(gpu_vendors(&[]).is_empty());
    }

    #[test]
    fn bootloader_and_filesystems() {
        let dir = std::env::temp_dir().join(format!("host-platform-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("entries")).unwrap();
        fs::write(dir.join("grub"), "").unwrap();
        assert_eq!(
            bootloader(&dir.join("grub"), &dir.join("entries"), true),
            "grub"
        );
        assert_eq!(
            bootloader(&dir.join("grub"), &dir.join("entries"), false),
            "systemd-boot",
            "grub without grub-mkconfig is not grub"
        );
        assert_eq!(
            bootloader(&dir.join("nothing"), &dir.join("nothing"), true),
            "none"
        );
        fs::remove_dir_all(&dir).unwrap();
        assert_eq!(
            filesystems("\next4\nntfs\n\nvfat\next4\n"),
            ["ext4", "ntfs", "vfat"]
        );
    }
}
