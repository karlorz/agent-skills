# Structure-only report repair is allowed; evidence rewrite is not

D already forbids rewriting a generated report to make lint pass. Live reports
still fail lint by inserting notes between `**Status:**` and the H1, localizing
ledger role tokens, and leaving bare `/tmp` paths. We will run a
**structure-only repair** after lint: it may insert or move the H1, prefix
English role tokens, and prefix `local-record:`. It must not change Status,
claims, URLs, Coverage, or invent hashes. Remaining lint errors stay in the
usage record. Rejected alternatives were prompt-only tightening (already
insufficient) and replacing a failed report with the Partial fallback (destroys
usable narrative).
