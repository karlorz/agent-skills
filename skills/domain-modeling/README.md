# Domain Modeling

Maintains a project's domain language while design work is happening. It keeps glossaries implementation-free and records ADRs only when a decision is hard to reverse, surprising without context, and based on a real trade-off.

```bash
codex plugin add domain-modeling@karlorz-agent-skills
claude plugin install domain-modeling@karlorz-agent-skills
```

The skill selects repository-local or SkillWiki-managed storage from the active project policy before writing.
