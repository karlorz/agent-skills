# Grok Search CLI Authentication Contract

The CLI authenticates against the hosted coordinator at `https://search.karldigi.dev` using hosted approve-and-poll.

## Credential Resolution Order

1. Environment variable: Non-empty `GROK_SEARCH_MCP_TOKEN`.
2. File token: `~/.config/grok-search/http-mcp.token`.

If the environment variable is present and rejected (HTTP 401), the CLI returns `env_token_rejected` and explains that the operator must update or unset the environment override. A file token cannot supersede an active environment variable.

If no token is found, read commands return `auth_required` instructing the user to run `auth-start`.

## State and File Permissions

- Storage directory: `~/.config/grok-search/` with permissions `0700` (POSIX).
- Token file: `~/.config/grok-search/http-mcp.token` with permissions `0600`.
- Metadata file: `~/.config/grok-search/token-meta.json` with permissions `0600`.
- Pending auth session: `~/.config/grok-search/cli-auth.json` with permissions `0600`.
- Auth lock: `~/.config/grok-search/cli-auth.lock` with permissions `0600`; both start and status acquire it. A lock is never stolen on age alone. Verify its process has stopped before manually removing a stale lock.
- Symbolic links (including dangling links and config parents) and unsafe ownership are rejected. Existing modes can only be tightened.
- Hosted file persistence requires POSIX storage. On Windows use an environment token; the CLI does not claim Unix modes enforce Windows ACLs.
- Files are updated using exclusive temporary files and atomic replacement.

## Auth Lifecycle

1. `auth-start`:
   - Makes a POST request to `https://search.karldigi.dev/auth/cli/start` with optional JSON fields:
     - `agent_id`: optional string identifying the host or agent requesting access (e.g. `muse`). Never logged as a secret.
     - `invite_code`: optional string invite code supplied by the operator. Never printed in logs or error messages.
   - The coordinator generates an `approveUrl` (using query `ref` for session pairing; appends `invite=<invite_code>` when invite is present, without overloading `ref`).
   - Persists pending session state (`authRunId`, `pollSecret`, `approveUrl`, `expiresAt`, `intervalSeconds`) privately in `cli-auth.json`.
   - Emits public parameters (`approveUrl`, `authRunId`, `expiresAt`, `intervalSeconds`) to `stdout`.
   - On interactive TTY terminals, renders a scannable QR code of `approveUrl` to `stderr`.
   - `pollSecret` is strictly excluded from `stdout`, `stderr`, logs, and QR codes.

2. `auth-status`:
   - Reads private `authRunId` and `pollSecret` from `cli-auth.json`.
   - Makes a GET request to `https://search.karldigi.dev/auth/cli/check?authRunId=<id>` with `X-CLI-Poll-Secret: <pollSecret>`.
   - Maps hosted check JSON `status` (not the coordinator's internal `AuthRunState` names) as follows:
     - `pending`, `awaiting_gateway`, `claiming`: returns `{ ok: true, data: { status: "pending", ... } }` with exit code `0`. Leaves `cli-auth.json` in place.
     - `success`, `ready`, `authenticated`: token-bearing. The hosted coordinator's first successful claim is `success` plus `token`. Extracts `token` / `accessToken` / `bearer`, atomically persists `http-mcp.token` and `token-meta.json`, deletes `cli-auth.json`, and returns `{ ok: true, data: { status: "authenticated" } }` with exit code `0`.
     - `consumed`: always fails `auth_exchange_failed` and removes pending state. An existing file may hold an older token and cannot prove this collection succeeded. A lost final response requires a new approval.
     - `cancelled`, `expired`, `failed`: deletes `cli-auth.json` and exits with an error status.
     - Any other check status: exits `auth_failed` with `retryable: true` and leaves `cli-auth.json` so a status mismatch cannot burn the session.

The CLI rejects approval URLs outside the pinned HTTPS origin, invalid or expired
start responses, private state bound to a different origin, and expired pending
runs before polling. A live pending approval cannot be overwritten by another
start. Token metadata derives expiry from the actual `expires_in` response;
metadata and token must both save before success. Partial save failures return an
error and discard a partial credential pair. A rejected environment token still
requires updating or unsetting that override; a saved file cannot supersede it.
