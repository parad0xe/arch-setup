//! The setup repository: reads the manifests of the modules
//! (`modules/*.toml`) into declarations, checks them against the files and
//! the hook scripts next to them, reads the profiles (`profiles/*.toml` and
//! a folder of the user's), and writes the profiles the user saves.
//!
//! The format of the manifests is docs/manifest.md of the repository.

mod error;
mod manifest;
mod profiles;
mod repository;

pub use error::RepoError;
pub use profiles::{read_profiles, valid_profile_name, write_profile};
pub use repository::Repository;
