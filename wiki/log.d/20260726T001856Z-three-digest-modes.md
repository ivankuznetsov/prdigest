# 2026-07-26 — Three digest modes

- Extracted one canonical collection engine shared by deterministic delivery,
  versioned facts JSON, and optional standalone prose.
- Added `prdigest facts` as the stable agent-facing boundary without schedule
  state, Telegram, or provider side effects.
- Added optional OpenAI-compatible prose for stdout or explicit Telegram
  delivery, with separate checkpoint-first replay and visible provider failures.
- Restricted plaintext provider endpoints to strict loopback hosts and rejected
  generated terminal controls before stdout, checkpoints, or Telegram.
- Added a PRDigest-owned, ClawHub-ready OpenClaw skill that validates facts
  schema version 1 and treats every pull-request field as untrusted data.
- Kept ClawHub publication, authenticated provider proof, release metadata,
  tagging, and gem publication outside this implementation.
