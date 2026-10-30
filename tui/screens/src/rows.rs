//! The lines of the lists: what each screen shows, built from the state.

use std::collections::BTreeMap;

use model::{InputValue, Plan, Reason, Registry, Selection, Unit, plan};

/// How a unit stands in the selection.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Mark {
    Selected,
    /// Added for a selected one: required by this unit.
    Added(String),
    None,
}

/// Where a unit sits in the tree of its parent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Tree {
    None,
    Middle,
    Last,
}

/// What an input shows as its value.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Shown {
    /// Answered, or the default.
    Value(String),
    /// A secret, answered or not.
    Secret { answered: bool },
    /// No answer and no default; required or not.
    Missing { required: bool },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Row {
    /// A module (or a unit, on the inputs screen): a band with counts.
    Section {
        id: String,
        name: String,
        selected: usize,
        total: usize,
        added: usize,
    },
    Unit {
        id: String,
        tree: Tree,
        mark: Mark,
    },
    Variant {
        unit: String,
        variant: String,
        option: String,
    },
    Profile {
        name: String,
    },
    /// The unfinished run.
    Resume {
        description: String,
    },
    /// The private repository in use, or none.
    Private {
        source: Option<String>,
    },
    Input {
        unit: String,
        input: String,
        shown: Shown,
    },
    Step {
        unit: String,
        reason: Reason,
    },
    LeftOut {
        unit: String,
        required_by: String,
    },
    Separator(String),
}

impl Row {
    /// The text the filter searches in.
    pub(crate) fn search_text(&self, registry: &Registry) -> String {
        match self {
            Row::Section { id, name, .. } => format!("{id} {name}"),
            Row::Unit { id, .. } | Row::Step { unit: id, .. } => {
                let unit = registry.unit(id);
                format!("{id} {}", unit.map(Unit::name).unwrap_or_default())
            }
            Row::Variant {
                unit,
                variant,
                option,
            } => format!("{unit} {variant} {option}"),
            Row::Profile { name } => name.clone(),
            Row::Resume { description } => description.clone(),
            Row::Private { source } => source.clone().unwrap_or_default(),
            Row::Input { unit, input, .. } => format!("{unit} {input}"),
            Row::LeftOut { unit, .. } => unit.clone(),
            Row::Separator(text) => text.clone(),
        }
    }

    /// A line the cursor can rest on.
    pub(crate) fn is_item(&self) -> bool {
        !matches!(self, Row::Separator(_))
    }
}

/// The units the selected ones require, each with the unit requiring it:
/// the plan's reasons for the units not picked.
pub(crate) fn implied(registry: &Registry, selection: &Selection) -> BTreeMap<String, String> {
    plan::build(registry, selection)
        .steps()
        .iter()
        .filter_map(|step| match step.reason() {
            Reason::RequiredBy(by) | Reason::DefaultOf(by) => {
                Some((step.unit().to_string(), by.clone()))
            }
            _ => None,
        })
        .collect()
}

/// The rows of the units screen: a band per module, its offered units with
/// the parts under their parent; for the files alone, the units with files.
pub(crate) fn units(registry: &Registry, selection: &Selection, files_only: bool) -> Vec<Row> {
    let implied = implied(registry, selection);
    let mark = |id: &str| {
        if selection.contains(id) {
            Mark::Selected
        } else if let Some(by) = implied.get(id) {
            Mark::Added(by.clone())
        } else {
            Mark::None
        }
    };
    let mut rows = Vec::new();
    for module in registry.modules() {
        let offered: Vec<&Unit> = module
            .units()
            .iter()
            .filter(|u| u.offered() && (!files_only || !u.files().is_empty()))
            .collect();
        if offered.is_empty() {
            continue;
        }
        let selected = offered
            .iter()
            .filter(|u| selection.contains(u.id()))
            .count();
        let added = offered
            .iter()
            .filter(|u| !selection.contains(u.id()) && implied.contains_key(u.id()))
            .count();
        rows.push(Row::Section {
            id: module.id().to_string(),
            name: module.name().to_string(),
            selected,
            total: offered.len(),
            added,
        });
        // Top-level units in order, each followed by its offered parts
        for unit in offered.iter().filter(|u| u.parent().is_none()) {
            rows.push(Row::Unit {
                id: unit.id().to_string(),
                tree: Tree::None,
                mark: mark(unit.id()),
            });
            let parts: Vec<&&Unit> = offered
                .iter()
                .filter(|p| p.parent() == Some(unit.id()))
                .collect();
            for (i, part) in parts.iter().enumerate() {
                let tree = if i + 1 == parts.len() {
                    Tree::Last
                } else {
                    Tree::Middle
                };
                rows.push(Row::Unit {
                    id: part.id().to_string(),
                    tree,
                    mark: mark(part.id()),
                });
            }
        }
        // Offered parts whose parent is not offered (it always runs)
        for part in offered.iter().filter(|p| {
            p.parent()
                .is_some_and(|parent| !offered.iter().any(|u| u.id() == parent))
        }) {
            rows.push(Row::Unit {
                id: part.id().to_string(),
                tree: Tree::None,
                mark: mark(part.id()),
            });
        }
    }
    rows
}

/// The option shown when none is picked.
pub(crate) fn default_option(variant: &model::Variant) -> &str {
    variant
        .default
        .as_deref()
        .or_else(|| {
            variant
                .options
                .iter()
                .find(|o| *o == "default")
                .map(String::as_str)
        })
        .or_else(|| variant.options.first().map(String::as_str))
        .unwrap_or_default()
}

/// The rows of the variants screen: the variants of every planned unit,
/// the ones that come in through `requires` included, with their option.
pub(crate) fn variants(registry: &Registry, selection: &Selection, plan: &Plan) -> Vec<Row> {
    let mut rows = Vec::new();
    for step in plan.steps() {
        let Some(unit) = registry.unit(step.unit()) else {
            continue;
        };
        if unit.variants().is_empty() {
            continue;
        }
        let picked = unit
            .variants()
            .iter()
            .filter(|v| selection.variant(unit.id(), &v.id).is_some())
            .count();
        rows.push(Row::Section {
            id: unit.id().to_string(),
            name: unit.name().to_string(),
            selected: picked,
            total: unit.variants().len(),
            added: 0,
        });
        for variant in unit.variants() {
            let option = selection
                .variant(unit.id(), &variant.id)
                .unwrap_or(default_option(variant))
                .to_string();
            rows.push(Row::Variant {
                unit: unit.id().to_string(),
                variant: variant.id.clone(),
                option,
            });
        }
    }
    rows
}

/// The rows of the inputs screen: the questions of the planned units.
pub(crate) fn inputs(registry: &Registry, selection: &Selection, plan: &Plan) -> Vec<Row> {
    let mut rows = Vec::new();
    for step in plan.steps() {
        let Some(unit) = registry.unit(step.unit()) else {
            continue;
        };
        if unit.inputs().is_empty() {
            continue;
        }
        let answered = unit
            .inputs()
            .iter()
            .filter(|i| selection.input(unit.id(), &i.id).is_some())
            .count();
        rows.push(Row::Section {
            id: unit.id().to_string(),
            name: unit.name().to_string(),
            selected: answered,
            total: unit.inputs().len(),
            added: 0,
        });
        for input in unit.inputs() {
            let shown = match (selection.input(unit.id(), &input.id), input.kind) {
                (answered, model::InputKind::Secret) => Shown::Secret {
                    answered: answered.is_some(),
                },
                (Some(InputValue::Flag(flag)), _) => {
                    Shown::Value(if *flag { "yes" } else { "no" }.to_string())
                }
                (Some(InputValue::Text(text)), _) => Shown::Value(text.clone()),
                (None, model::InputKind::Bool) => Shown::Value(
                    if input.default.as_deref() == Some("true") {
                        "yes (default)"
                    } else {
                        "no (default)"
                    }
                    .to_string(),
                ),
                (None, _) => match &input.default {
                    Some(default) => Shown::Value(format!("{default} (default)")),
                    None => Shown::Missing {
                        required: input.required,
                    },
                },
            };
            rows.push(Row::Input {
                unit: unit.id().to_string(),
                input: input.id.clone(),
                shown,
            });
        }
    }
    rows
}

/// The rows of the summary: the steps in order, then the units left out.
pub(crate) fn summary(plan: &Plan) -> Vec<Row> {
    let mut rows: Vec<Row> = plan
        .steps()
        .iter()
        .map(|s| Row::Step {
            unit: s.unit().to_string(),
            reason: s.reason().clone(),
        })
        .collect();
    if !plan.left_out().is_empty() {
        rows.push(Row::Separator(
            "Required, but not for this machine".to_string(),
        ));
        rows.extend(plan.left_out().iter().map(|(unit, by)| Row::LeftOut {
            unit: unit.clone(),
            required_by: by.clone(),
        }));
    }
    rows
}

/// The inputs without an answer or a default that are required.
pub(crate) fn missing_required(
    registry: &Registry,
    selection: &Selection,
    plan: &Plan,
) -> Vec<(String, String)> {
    plan.steps()
        .iter()
        .filter_map(|step| registry.unit(step.unit()))
        .flat_map(|unit| {
            unit.inputs()
                .iter()
                .filter(|input| {
                    input.required
                        && input.default.is_none()
                        && selection.input(unit.id(), &input.id).is_none()
                })
                .map(|input| (unit.id().to_string(), input.id.clone()))
                .collect::<Vec<_>>()
        })
        .collect()
}
