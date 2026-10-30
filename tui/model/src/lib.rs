//! What the setup is made of, and what a selection of it becomes. Pure: no
//! file, no process, no environment.
//!
//! A reader (the `repo` crate) produces [`Declarations`] from the manifests;
//! [`Registry::new`] validates them against the [`Platform`] of a machine and
//! tells which units are available and offered. A [`Profile`] resolves into
//! a [`Selection`]; [`plan::build`] turns a selection into the ordered
//! [`Plan`] of the run.
//!
//! The types with an invariant ([`Registry`], [`Unit`], [`Profiles`],
//! [`Condition`]) have private fields and a constructor that validates;
//! the plain values of the manifests ([`declarations`], [`Platform`],
//! [`Profile`]) have public fields.

mod declarations;
pub mod plan;
mod platform;
mod profile;
mod registry;
mod selection;

pub use declarations::{
    Declarations, FileEntry, Fragment, Hook, Input, InputKind, InputOption, Merge, Mode,
    ModuleDeclaration, Package, Service, UnitDeclaration, Variant,
};
pub use plan::{Plan, Reason, Step};
pub use platform::{Condition, ConditionError, Expected, Platform};
pub use profile::{Profile, ProfileError, Profiles, Resolved};
pub use registry::{HookRun, Module, Registry, RegistryError, Unit};
pub use selection::{InputValue, Selection};
