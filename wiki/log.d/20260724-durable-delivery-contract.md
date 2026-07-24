# 2026-07-24 — Durable delivery and embedding contract

- Added repeatable `--repo owner/name` overrides and the versioned
  `prdigest-result` JSON contract for registry-driven callers such as Hive.
- Made the rendered chunk list durable per digest date and resume delivery at the
  next definitely-unsent chunk.
- Classified deterministic Telegram failures as permanent, parked ambiguous
  transport outcomes, and retained bounded retry only for definite transient
  responses.
- Added a two-project, five-PR multi-chunk regression covering escaped content,
  links, balanced HTML, complete sections, and the final footer.
