# Changelog

All notable changes to this skill are documented in this file.

## [0.1.0] - 2026-09-16

- Port the upstream composition concept as a cross-surface adapter.
- Depend on the maintained `grill-me:grilling` and `domain-modeling:domain-modeling` skills instead of duplicating either implementation.
- Permit model invocation so dev-loop can select the adapter when configured, while retaining attended-session, missing-dependency, SkillWiki routing, and caller-facing requirements-summary contracts.
