//! What the machine is, for the screens: host, system, CPU, GPU, boot,
//! memory and disk.

use std::path::Path;

use crate::probe::{output, read, succeeds};

/// Used and total bytes of a resource.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Usage {
    pub used: u64,
    pub total: u64,
}

impl Usage {
    /// Used over total, between 0 and 1.
    pub fn ratio(&self) -> f64 {
        if self.total == 0 {
            0.0
        } else {
            (self.used as f64 / self.total as f64).clamp(0.0, 1.0)
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Machine {
    pub host: String,
    /// The distribution, e.g. "Arch Linux".
    pub system: String,
    pub kernel: String,
    pub cpu: String,
    /// The first graphics card, when there is one.
    pub gpu: Option<String>,
    /// The boot loader, when known.
    pub bootloader: Option<String>,
    /// The hypervisor, inside a virtual machine.
    pub virtualization: Option<String>,
    pub memory: Option<Usage>,
    pub disk: Option<Usage>,
}

/// Reads what this machine is.
pub fn probe_machine() -> Machine {
    let bootloader = match crate::platform::bootloader(
        Path::new("/etc/default/grub"),
        Path::new("/boot/loader/entries"),
        crate::probe::installed("grub-mkconfig"),
    )
    .as_str()
    {
        "grub" => Some("GRUB".to_string()),
        "systemd-boot" => Some("systemd-boot".to_string()),
        _ => None,
    };
    Machine {
        host: read("/etc/hostname")
            .filter(|h| !h.is_empty())
            .or_else(|| output("uname", &["-n"]))
            .unwrap_or_default(),
        system: pretty_name(&read("/etc/os-release").unwrap_or_default()),
        kernel: read("/proc/sys/kernel/osrelease").unwrap_or_default(),
        cpu: cpu_model(&read("/proc/cpuinfo").unwrap_or_default())
            .or_else(|| read("/proc/device-tree/model"))
            .unwrap_or_else(|| "unknown".to_string()),
        gpu: ["::0300", "::0302", "::0380"]
            .iter()
            .find_map(|class| gpu_name(&output("lspci", &["-mm", "-d", class])?)),
        bootloader,
        virtualization: output("systemd-detect-virt", &[])
            .filter(|v| v != "none" && succeeds("systemd-detect-virt", &["--quiet"])),
        memory: memory(&read("/proc/meminfo").unwrap_or_default()),
        disk: disk(&output("df", &["-kP", "/"]).unwrap_or_default()),
    }
}

pub(crate) fn pretty_name(os_release: &str) -> String {
    os_release
        .lines()
        .find_map(|line| line.strip_prefix("PRETTY_NAME="))
        .map(|value| value.trim().trim_matches('"').to_string())
        .unwrap_or_else(|| "Linux".to_string())
}

pub(crate) fn cpu_model(cpuinfo: &str) -> Option<String> {
    cpuinfo
        .lines()
        .find_map(|line| line.strip_prefix("model name"))
        .and_then(|rest| rest.split_once(':'))
        .map(|(_, value)| value.trim().to_string())
}

/// The vendor and device of the first line of `lspci -mm`.
pub(crate) fn gpu_name(lspci: &str) -> Option<String> {
    let line = lspci.lines().next()?;
    let fields: Vec<&str> = line.split('"').collect();
    if fields.len() < 6 {
        return None;
    }
    let vendor = fields[3]
        .trim_end_matches(" Corporation")
        .trim_end_matches(" Inc.");
    Some(format!("{vendor} {}", fields[5]))
}

pub(crate) fn memory(meminfo: &str) -> Option<Usage> {
    let kib = |key: &str| -> Option<u64> {
        meminfo
            .lines()
            .find_map(|line| line.strip_prefix(key))
            .and_then(|rest| rest.trim_start_matches(':').split_whitespace().next())
            .and_then(|value| value.parse().ok())
    };
    let total = kib("MemTotal")? * 1024;
    let available = kib("MemAvailable")? * 1024;
    Some(Usage {
        used: total.saturating_sub(available),
        total,
    })
}

pub(crate) fn disk(df: &str) -> Option<Usage> {
    let fields: Vec<&str> = df.lines().nth(1)?.split_whitespace().collect();
    let total: u64 = fields.get(1)?.parse().ok()?;
    let used: u64 = fields.get(2)?.parse().ok()?;
    Some(Usage {
        used: used * 1024,
        total: total * 1024,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_system_files_are_parsed() {
        assert_eq!(
            pretty_name("ID=arch\nPRETTY_NAME=\"Arch Linux\"\n"),
            "Arch Linux"
        );
        assert_eq!(pretty_name(""), "Linux");
        assert_eq!(
            cpu_model("model name\t: Intel(R) Core(TM) i5\nflags: x\n").as_deref(),
            Some("Intel(R) Core(TM) i5")
        );
        assert_eq!(
            gpu_name("01:00.0 \"VGA compatible controller\" \"NVIDIA Corporation\" \"TU106 [GeForce RTX 2070]\" -ra1 \"\" \"\"\n").as_deref(),
            Some("NVIDIA TU106 [GeForce RTX 2070]")
        );
        assert_eq!(gpu_name(""), None);
        let memory = memory(
            "MemTotal:       16000 kB\nMemFree:         1000 kB\nMemAvailable:   12000 kB\n",
        )
        .unwrap();
        assert_eq!(
            memory,
            Usage {
                used: 4000 * 1024,
                total: 16000 * 1024
            }
        );
        assert!((memory.ratio() - 0.25).abs() < 1e-9);
        let disk = disk("Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda2 1000 250 750 25% /\n").unwrap();
        assert_eq!(
            disk,
            Usage {
                used: 250 * 1024,
                total: 1000 * 1024
            }
        );
        assert_eq!(Usage { used: 1, total: 0 }.ratio(), 0.0);
    }
}
