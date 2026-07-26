# Architecture

PRDigest is a synchronous oneshot with one canonical collection boundary and
three presentation modes. `CLI` resolves capability-scoped configuration and
secrets. `Collector` combines pure civil-time windows with the `GitHub` client
and returns a `DayDigest`; scheduling, JSON facts, deterministic HTML, and
optional prose all consume that same value. Dependencies are injectable so the
automated suite never contacts a real service.

`Runner` is the original deterministic path: it coordinates schedule/state,
renders safe Telegram HTML, and delivers to one allowlisted chat. `FactsRunner`
bypasses schedule state, rendering, Telegram, and providers to serialize one
date as `prdigest-facts` schema version 1. `ProseRunner` passes that exact facts
document to an `OpenAICompatible` Chat Completions client, then returns raw
plain text or safely escapes and delivers it only when `--deliver` is explicit.
Remote providers require HTTPS, plaintext HTTP is loopback-only, and generated
C0/C1 terminal controls are rejected before stdout or delivery. No provider
configuration is consulted by deterministic `run` or `facts`.

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

Prose delivery has a separate `delivery_path/prose` checkpoint namespace. Its
lazy chunk factory runs while the per-date checkpoint lock is held only when no
payload exists. Collection, provider generation, and safe rendering therefore
finish before the final chunks are persisted and before Telegram starts. A
partial or completed retry loads the exact stored payload and bypasses both
GitHub and the provider, preventing regenerated prose from changing the replay.

The repository-owned OpenClaw skill is another presentation adapter over
`prdigest facts`. It validates the facts schema and success envelope, treats all
values as untrusted data, and writes prose without a second GitHub query,
Telegram delivery, or use of PRDigest's provider path. The ClawHub text bundle
and Ruby gem are separate distribution artifacts.
