# Changelog

## [0.1.1] - 2026-10-20

- Separate static installed-file inventory estimates from CLI-discovered skill rows, unique names, duplicate-name groups, and source counts.
- Keep model visibility explicitly unknown when inspect metadata lacks prompt-level evidence; label token estimates and warning thresholds by their basis.
- Parse multiline skill descriptions and Windows BOM/CRLF frontmatter consistently while retaining duplicate rows in cost estimates.
- Bind Grok probes to the audited home, clear inherited overlays, disable update checks, and handle timeouts, malformed output, and UTF-8 decoding safely.
- Reuse inspect version metadata to avoid redundant CLI launches and derive unique-name totals without duplicate state.
- Add isolated fixture, standalone parser parity, version fallback, and redaction regressions.

## [0.1.0] - 2026-09-20

- First read-only `harness-doctor` release for Claude, Grok, Codex, and Cursor.
- Normalized `harness-doctor.v1` JSON plus human report.
- Fake-home tests cover adapters, insufficient windows, passive/no-signal, and redaction.
