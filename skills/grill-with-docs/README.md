# Grill with Docs

Composes the separately maintained `grill-me:grilling` interview engine with `domain-modeling:domain-modeling` in one attended session.

## Install

Install all three packages because plugin manifests do not provide an automatic inter-plugin dependency field:

```bash
codex plugin add grill-me@karlorz-agent-skills
codex plugin add domain-modeling@karlorz-agent-skills
codex plugin add grill-with-docs@karlorz-agent-skills

claude plugin install grill-me@karlorz-agent-skills
claude plugin install domain-modeling@karlorz-agent-skills
claude plugin install grill-with-docs@karlorz-agent-skills
```

The adapter fails clearly when either dependency is unavailable. It does not carry a duplicate copy of the `grilling` skill.
