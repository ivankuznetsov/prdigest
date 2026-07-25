# 2026-07-25 — Delivery contract wiki refresh

Coalesced wiki coverage for `ff62de058664f13a602b1d361dc2b9250026bf6a`
and `29f3d11d7630ba5e153a2b715dfa6f4d11cb1af9`.

- Documented repeatable repository overrides, the versioned JSON result
  envelope, delivery progress, and public exit semantics.
- Documented the separate date cursor and per-date delivery-checkpoint schema,
  transitions, locking, retry, resume, and fail-closed recovery behavior.
- Replaced the stale at-least-once decision and clarified that explicit replay
  bypasses the date cursor but still honors the delivery checkpoint.
