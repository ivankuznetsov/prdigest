# Wiki Changelog

Append-only log of all wiki operations.

<!-- BEGIN GENERATED WIKI LOG FRAGMENTS -->
# 2026-07-25 — Delivery contract wiki refresh

Coalesced wiki coverage for `ff62de058664f13a602b1d361dc2b9250026bf6a`
and `29f3d11d7630ba5e153a2b715dfa6f4d11cb1af9`.

- Documented repeatable repository overrides, the versioned JSON result
  envelope, delivery progress, and public exit semantics.
- Documented the separate date cursor and per-date delivery-checkpoint schema,
  transitions, locking, retry, resume, and fail-closed recovery behavior.
- Replaced the stale at-least-once decision and clarified that explicit replay
  bypasses the date cursor but still honors the delivery checkpoint.

# 2026-07-24 — Accept Octokit timestamp objects

GitHub search mapping now accepts both ISO-8601 strings and the `Time` objects
that Octokit materializes in real responses. Repository and half-open UTC-window
validation still run against the normalized UTC timestamp.

The regression test uses the production-shaped `Time` value so offline fixtures
cannot hide this adapter boundary again.

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

# 2026-07-16 — PRDigest v0.1.0 implementation

Implemented the production oneshot from the Ruby scaffold: timezone-correct
windows, atomic state and catch-up, complete GitHub fetching, deterministic
Telegram HTML, guarded delivery, runner modes, result/exit contracts, and
production packaging.

Automated verification is offline and covers Ruby behavior, deterministic gem
contents, container/systemd contracts, and clean-install smoke scripts. The CI
matrix runs Ruby 3.2–3.4 plus isolated gem, Docker, and systemd gates.

Manual credentialed smokes, the clean VPS walkthrough, and independent review
remain release gates. No tag, publication, release, or live external request was
created during implementation.
<!-- END GENERATED WIKI LOG FRAGMENTS -->
