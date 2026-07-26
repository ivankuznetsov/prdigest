# Changelog

## Unreleased

- Add a deterministic `prdigest facts` JSON contract over the canonical
  collection engine without scheduling, Telegram, or provider side effects.
- Add optional OpenAI-compatible prose for stdout or explicit checkpointed
  Telegram delivery, with provider failures kept visible.
- Restrict plaintext provider URLs to strict loopback hosts and reject generated
  terminal control characters before output or delivery.
- Add a repository-owned, ClawHub-ready OpenClaw skill that writes prose only
  from validated PRDigest facts.
- Prove the facts command from an isolated installed gem without provider or
  network access beyond the stubbed GitHub boundary.

## 0.1.1 - 2026-07-25

- Accept Octokit `Time` objects as well as ISO-8601 strings for pull-request
  merge timestamps, fixing malformed-response failures against live GitHub data.

## 0.1.0 - 2026-07-16

- Add timezone-correct daily windows, atomic versioned state, and capped catch-up.
- Fetch complete merged-PR results with deterministic ordering and optional stats.
- Render safe, bounded Telegram HTML and deliver only to an allowlisted chat.
- Persist stable rendered chunks and resume at the next definitely-unsent chunk.
- Park permanent and ambiguous Telegram failures instead of replaying accepted messages.
- Add repeatable `--repo owner/name` input and a versioned JSON embedding contract.
- Add scheduled, explicit replay, dry-run, JSON, and stable exit-code contracts.
- Add non-root container, hardened systemd units, offline tests, and release smokes.

No tag, gem publication, or GitHub release is created by this preparation.
