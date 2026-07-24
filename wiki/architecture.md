# Architecture

PRDigest is a synchronous oneshot. `CLI` resolves configuration and secrets,
then `Runner` coordinates pure time/schedule logic, atomic `State`, the `GitHub`
client, `Renderer`, and allowlist-guarded `Telegram` delivery. Dependencies are
injectable so the automated suite never contacts a real service.

Scheduled real runs read timezone-bound state, checkpoint an over-cap skipped
prefix, and process retained dates oldest-first. For each date, the clock derives
a half-open UTC window, GitHub pagination and optional details complete, rendering
produces every valid HTML chunk, delivery finishes, and only then state advances.
Search merge timestamps are normalized from either Octokit's runtime `Time`
objects or fixture/API ISO-8601 strings before the repository/window check.
Before the first request, a separate per-date delivery checkpoint durably stores
the rendered payload, chat, repository scope, and next unsent chunk. Definite
acceptance advances that checkpoint; bounded retry applies only to definite
429/5xx rejection. Permanent responses and ambiguous transport outcomes park the
checkpoint and fail closed. A date-cursor failure after complete delivery can
therefore be retried without sending accepted chunks again.

Explicit replay and dry-run bypass state. Dry-run also bypasses Telegram. Empty
days either send the configured escaped message or settle through an explicit
suppression outcome. The systemd oneshot is the date-scheduling concurrency
boundary. A nonblocking per-date delivery lock additionally prevents two
processes from sending the same checkpoint. The repeatable CLI
`--repo owner/name` override is the embedding boundary for an external project
registry such as Hive; PRDigest remains the only fetch, render, chunk, and
delivery engine.
