# Architecture

PRDigest is a synchronous oneshot. `CLI` resolves configuration and secrets,
then `Runner` coordinates pure time/schedule logic, atomic `State`, the `GitHub`
client, `Renderer`, and allowlist-guarded `Telegram` delivery. Dependencies are
injectable so the automated suite never contacts a real service.

Scheduled real runs read timezone-bound state, checkpoint an over-cap skipped
prefix, and process retained dates oldest-first. For each date, the clock derives
a half-open UTC window, GitHub pagination and optional details complete, rendering
produces every valid HTML chunk, delivery finishes, and only then state advances.
Failures stop the loop and retain the current day for at-least-once retry.

Explicit replay and dry-run bypass state. Dry-run also bypasses Telegram. Empty
days either send the configured escaped message or settle through an explicit
suppression outcome. The systemd oneshot is the v0.1.0 concurrency boundary.
