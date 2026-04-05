# Routing Rules

## TL;DR

- Dynamically scan `5️⃣-Projects/` to detect project folders.
- First-mentioned project in topic wins for cross-cutting queries.
- Research keywords fall back to `5️⃣-Projects/Research/`.
- Unknown topics land in `0️⃣-Inbox/` with an advisory.
- Flags `--folder` and `--draft` override all automatic routing.

## Auto-Routing Algorithm

```
INPUT: topic string, optional --folder flag, optional --draft flag

1. IF --folder <path> is set:
   VALIDATE path exists or can be created
   RETURN <path>

2. IF --draft is set:
   RETURN "0️⃣-Inbox/"

3. DYNAMICALLY LIST project folders:
   - Scan 5️⃣-Projects/GitHub/*/
   - Scan 5️⃣-Projects/Infrastructure/*/
   - Collect folder names as project_names[]

4. NORMALIZE topic to lowercase

5. FOR EACH project_name in project_names (order by first mention in topic):
   IF topic contains project_name (case-insensitive):
     RETURN "5️⃣-Projects/GitHub/<project_name>/" or
            "5️⃣-Projects/Infrastructure/<project_name>/"
     (whichever matches)

6. IF topic contains research keywords:
   keywords = ["research", "study", "analysis", "comparison", "overview",
               "deep dive", "exploration", "investigation", "survey"]
   IF any keyword in topic:
     RETURN "5️⃣-Projects/Research/"

7. DEFAULT:
   EMIT advisory: "No project match found; routing to Inbox for manual triage"
   RETURN "0️⃣-Inbox/"
```

## Filename Generation

```
INPUT: topic string, target folder

1. SLUGIFY topic:
   - Lowercase
   - Replace spaces and special chars with hyphens
   - Remove consecutive hyphens
   - Trim to 50 chars max

2. APPEND suffix: "-deep-research"

3. CHECK for existing file at <folder>/<slug>-deep-research.md

4. IF exists:
   APPEND date: "-<YYYY-MM-DD>"
   Example: k8s-networking-deep-research-2026-03-27.md

5. RETURN final filename
```

## Cross-Cutting Topic Resolution

When a topic mentions multiple projects, the **first-mentioned** project wins.

Examples:

| Topic | First Match | Route |
|-------|-------------|-------|
| "K8s networking for cmux" | cmux | `5️⃣-Projects/GitHub/cmux/` |
| "cmux and trends integration" | cmux | `5️⃣-Projects/GitHub/cmux/` |
| "Compare trends vs cmux approach" | trends | `5️⃣-Projects/GitHub/trends/` |
| "React server components" | (none) | `5️⃣-Projects/Research/` |
| "GraphQL best practices" | (none) | `5️⃣-Projects/Research/` |
| "Random thoughts" | (none) | `0️⃣-Inbox/` |

## Existing Note Detection

Before writing, check for existing notes on the same topic:

```
1. SEARCH vault for:
   - Title containing topic slug
   - Tags matching topic keywords
   - Headings matching topic phrases

2. IF existing notes found:
   - Add wikilinks to them in Related Notes section
   - Consider whether new note is needed or if existing note should be updated
   - If very similar note exists (>80% title match), warn user

3. PROCEED with new note creation (user can manually merge later)
```

## Implementation Notes

- Use `rg --files`, `find`, or `ls` to dynamically discover project folders rather than hardcoding.
- Project folder names are case-insensitive for matching but preserve original case in paths.
- The `5️⃣-Projects/Research/` folder should exist; create it if missing.
- Routing decisions should be logged in the final report for transparency.

## Related

- [[vault-operations-index|Vault Operations Index]]
