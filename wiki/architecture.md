# Architecture

PRDigest is a synchronous oneshot with one canonical collection boundary and
two public commands. `CLI` resolves capability-scoped configuration and secrets.
`Collector` combines civil-time windows with the `GitHub` client and returns a
`DayDigest`; both agent facts and provider prose consume that same value.
Dependencies are injectable so the automated suite never contacts a real
service.

`FactsRunner` serializes one explicit date or yesterday as `prdigest-facts`
schema version 1. It bypasses Telegram, delivery state, and providers.
`ProseRunner` passes that exact facts document to an `OpenAICompatible` Chat
Completions client, then returns plain text or delivers it when `--deliver` is
explicit. Remote providers require HTTPS, plaintext HTTP is loopback-only, and
generated C0/C1 terminal controls are rejected before stdout or delivery.
`prdigest facts` never consults provider configuration.

For both commands, the clock derives a half-open UTC window for one configured
local date. GitHub pagination and optional details complete before the result is
exposed. Search merge timestamps are normalized from either Octokit's runtime
`Time` objects or fixture/API ISO-8601 strings before the repository/window
check. Repeatable `--repo owner/name` arguments override configured repository
scope without changing collection or ordering rules.

Prose delivery stores plain-text chunks under `delivery_path/prose` before the
first Telegram request. Its lazy chunk factory runs under the per-date
checkpoint lock only when no payload exists. A partial or completed retry loads
the exact stored payload and bypasses GitHub and the provider. Definite
acceptance advances the checkpoint; bounded retry applies only to definite
429/5xx rejection. Permanent responses and ambiguous transport outcomes park
the checkpoint and fail closed.

The supplied systemd oneshot invokes `prdigest prose --deliver`; the timer is the
daily scheduling boundary. PRDigest has no date cursor or catch-up engine.
Missed dates are explicit `--date` invocations.

The repository-owned OpenClaw skill is an agent presentation adapter over
`prdigest facts`. It validates the facts schema and success envelope, treats all
values as untrusted data, and writes prose without a second GitHub query,
Telegram delivery, or use of PRDigest's provider path. The ClawHub text bundle
and Ruby gem are separate distribution artifacts.
