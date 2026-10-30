//! What a selection becomes: the units that run, in order, with why each
//! one is there.

use std::collections::{BTreeMap, BTreeSet};

use crate::registry::Registry;
use crate::selection::Selection;

/// Why a unit is in the plan.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Reason {
    /// Runs in every run.
    Always,
    /// Selected.
    Picked,
    /// Required by this unit.
    RequiredBy(String),
    /// The default part of this unit's choice, none being picked.
    DefaultOf(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Step {
    unit: String,
    reason: Reason,
}

impl Step {
    pub fn unit(&self) -> &str {
        &self.unit
    }

    pub fn reason(&self) -> &Reason {
        &self.reason
    }
}

/// The steps of a run, in order, and the required units left out because
/// they do not apply to the machine.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Plan {
    steps: Vec<Step>,
    left_out: Vec<(String, String)>,
}

impl Plan {
    pub fn steps(&self) -> &[Step] {
        &self.steps
    }

    pub fn is_empty(&self) -> bool {
        self.steps.is_empty()
    }

    pub fn step(&self, unit: &str) -> Option<&Step> {
        self.steps.iter().find(|s| s.unit == unit)
    }

    /// The units required but unavailable: (unit, required by).
    pub fn left_out(&self) -> &[(String, String)] {
        &self.left_out
    }

    /// The plan without the steps `keep` refuses; what was left out stays.
    pub fn keeping(&self, mut keep: impl FnMut(&Step) -> bool) -> Plan {
        Plan {
            steps: self.steps.iter().filter(|s| keep(s)).cloned().collect(),
            left_out: self.left_out.clone(),
        }
    }
}

/// The plan of a selection: the always units first, then the selected ones
/// and what they require, each after what it requires and what it is
/// after, the declaration order breaking ties. Selected units unknown to
/// the registry or unavailable are ignored.
pub fn build(registry: &Registry, selection: &Selection) -> Plan {
    let mut reasons: BTreeMap<String, Reason> = BTreeMap::new();
    let mut left_out = Vec::new();
    for unit in registry.units().filter(|u| u.always()) {
        reasons.insert(unit.id().to_string(), Reason::Always);
    }
    for id in selection.units() {
        if registry.unit(id).is_some_and(|u| u.available()) && !reasons.contains_key(id) {
            reasons.insert(id.to_string(), Reason::Picked);
        }
    }
    // The requirements, recursively, in a stable order
    let mut pending: Vec<String> = reasons.keys().cloned().collect();
    while let Some(id) = pending.pop() {
        let unit = registry.unit(&id).expect("only known units are planned");
        for required in unit.requires() {
            let Some(target) = registry.unit(required) else {
                continue;
            };
            if !target.available() {
                left_out.push((required.clone(), id.clone()));
                continue;
            }
            if !reasons.contains_key(required) {
                reasons.insert(required.clone(), Reason::RequiredBy(id.clone()));
                pending.push(required.clone());
            }
        }
        // One of the exclusive parts comes with the unit: the default, or
        // the first available one
        if let Some(choice) = unit.choice() {
            if choice.parts.iter().any(|part| reasons.contains_key(part)) {
                continue;
            }
            let available = |part: &String| registry.unit(part).is_some_and(|u| u.available());
            let part = std::iter::once(&choice.default)
                .chain(&choice.parts)
                .find(|part| available(part));
            match part {
                Some(part) => {
                    reasons.insert(part.clone(), Reason::DefaultOf(id.clone()));
                    pending.push(part.clone());
                }
                None => left_out.push((choice.default.clone(), id.clone())),
            }
        }
    }

    // Kahn's algorithm, picking the earliest declared unit among the ready
    // ones, the always units before the others
    let planned: BTreeSet<&str> = reasons.keys().map(String::as_str).collect();
    let mut remaining: Vec<&str> = registry
        .units()
        .filter(|u| planned.contains(u.id()))
        .map(|u| u.id())
        .collect();
    remaining.sort_by_key(|id| {
        (
            !registry.unit(id).is_some_and(|u| u.always()),
            registry.position(id),
        )
    });
    let mut steps = Vec::new();
    let mut done: BTreeSet<&str> = BTreeSet::new();
    while !remaining.is_empty() {
        let ready = remaining.iter().position(|id| {
            let unit = registry.unit(id).expect("planned units exist");
            unit.requires()
                .iter()
                .chain(unit.after())
                .all(|dep| !planned.contains(dep.as_str()) || done.contains(dep.as_str()))
        });
        // The registry refuses cycles, so a unit is always ready
        let id = remaining.remove(ready.unwrap_or(0));
        done.insert(id);
        steps.push(Step {
            unit: id.to_string(),
            reason: reasons[id].clone(),
        });
    }
    left_out.sort();
    left_out.dedup();
    Plan { steps, left_out }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::registry::tests::{declarations, platform};

    fn ids(plan: &Plan) -> Vec<&str> {
        plan.steps().iter().map(Step::unit).collect()
    }

    #[test]
    fn always_first_then_requirements_and_order() {
        let reg = Registry::new(declarations(), &platform()).unwrap();
        let mut sel = Selection::new();
        sel.select("slow");
        sel.select("elem");
        sel.select("early");
        sel.select("late");
        let plan = build(&reg, &sel);
        assert_eq!(
            ids(&plan),
            ["base", "quick", "slow", "part", "elem", "late", "early"],
            "a part comes before the parent requiring it"
        );
        assert_eq!(plan.step("base").unwrap().reason(), &Reason::Always);
        assert_eq!(
            plan.step("quick").unwrap().reason(),
            &Reason::RequiredBy("slow".into())
        );
        assert_eq!(
            plan.step("part").unwrap().reason(),
            &Reason::RequiredBy("elem".into())
        );
        assert_eq!(plan.step("early").unwrap().reason(), &Reason::Picked);
        assert!(plan.left_out().is_empty());
    }

    #[test]
    fn unavailable_requirements_are_left_out_and_noted() {
        let mut decls = declarations();
        let mut wants = crate::registry::tests::unit("wants-arm");
        wants.requires = vec!["arm".into()];
        decls.modules[0].units.push(wants);
        let reg = Registry::new(decls, &platform()).unwrap();
        let mut sel = Selection::new();
        sel.select("wants-arm");
        sel.select("arm");
        let plan = build(&reg, &sel);
        assert_eq!(
            ids(&plan),
            ["base", "wants-arm"],
            "an unavailable unit is never planned, even selected"
        );
        assert_eq!(
            plan.left_out(),
            [("arm".to_string(), "wants-arm".to_string())]
        );
    }

    #[test]
    fn an_empty_selection_plans_the_always_units_only() {
        let reg = Registry::new(declarations(), &platform()).unwrap();
        let plan = build(&reg, &Selection::new());
        assert_eq!(ids(&plan), ["base"]);
    }
}
