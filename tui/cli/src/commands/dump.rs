//! The platform, the modules with their units as the registry sees them,
//! and the profiles, as JSON.

use std::process::ExitCode;

use anyhow::Result;
use model::{InputKind, Mode, Unit};
use serde_json::{Value, json};

use crate::commands::common::Setup;
use crate::config::Config;
use crate::console::Console;
use crate::private;

pub fn dump(config: Config, console: &mut Console) -> Result<ExitCode> {
    let private = private::initial(&config, console, None)?;
    let setup = Setup::load(config, private)?;
    let platform = &setup.platform;
    let modules: Vec<Value> = setup
        .registry
        .modules()
        .iter()
        .map(|module| {
            json!({
                "id": module.id(),
                "name": module.name(),
                "about": module.about(),
                "root": module.root(),
                "units": module.units().iter().map(unit_json).collect::<Vec<_>>(),
            })
        })
        .collect();
    let profiles: Vec<Value> = setup
        .profiles
        .iter()
        .map(|profile| {
            json!({
                "name": profile.name,
                "about": profile.about,
                "extends": profile.extends,
                "units": profile.units,
                "exclude": profile.exclude,
                "variants": profile.variants,
                "inputs": profile.inputs.iter().map(|(k, v)| (k.clone(), Value::String(v.to_string()))).collect::<serde_json::Map<_, _>>(),
            })
        })
        .collect();
    let dump = json!({
        "platform": {
            "distro": platform.distro,
            "arch": platform.arch,
            "cpu": platform.cpu,
            "gpu": platform.gpu,
            "vm": platform.vm,
            "apple_silicon": platform.apple_silicon,
            "bootloader": platform.bootloader,
            "filesystems": platform.filesystems,
        },
        "repositories": {
            "public": setup.public.root(),
            "private": setup.private.as_ref().map(|p| &p.root),
        },
        "modules": modules,
        "profiles": profiles,
    });
    println!("{}", serde_json::to_string_pretty(&dump)?);
    Ok(ExitCode::SUCCESS)
}

fn unit_json(unit: &Unit) -> Value {
    json!({
        "id": unit.id(),
        "name": unit.name(),
        "about": unit.about(),
        "parent": unit.parent(),
        "always": unit.always(),
        "attended": unit.attended(),
        "available": unit.available(),
        "offered": unit.offered(),
        "requires": unit.requires(),
        "after": unit.after(),
        "packages": unit.packages(),
        "aur": unit.aur(),
        "services": unit.services().iter().map(|s| json!({ "name": s.name, "now": s.now, "force": s.force })).collect::<Vec<_>>(),
        "files": unit.files().iter().map(|f| json!({
            "source": f.source,
            "target": f.target,
            "mode": match f.mode { Mode::Symlink => "symlink", Mode::Copy => "copy" },
            "contents": f.contents,
            "backup": f.backup,
            "permissions": f.permissions.map(|p| format!("{p:o}")),
        })).collect::<Vec<_>>(),
        "variants": unit.variants().iter().map(|v| json!({ "id": v.id, "name": v.name, "options": v.options, "default": v.default })).collect::<Vec<_>>(),
        "inputs": unit.inputs().iter().map(|i| json!({
            "id": i.id,
            "prompt": i.prompt,
            "kind": match i.kind { InputKind::Text => "text", InputKind::Bool => "bool", InputKind::Secret => "secret", InputKind::Choice => "choice" },
            "default": i.default,
            "required": i.required,
            "options": i.options.iter().map(|o| json!({ "name": o.name, "value": o.value })).collect::<Vec<_>>(),
            "custom": i.custom,
        })).collect::<Vec<_>>(),
        "hooks": unit.hooks().collect::<Vec<_>>(),
        "extended_by": unit.extended_by(),
    })
}
