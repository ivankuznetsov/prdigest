# 2026-07-26 — Trusted RubyGems publishing

Added one exact-tag RubyGems release authority using GitHub OIDC trusted
publishing. New tags trigger it automatically, while manual dispatch can
backfill an existing immutable tag such as v0.1.1.

The workflow validates the vX.Y.Z tag against the packaged version, runs unit
and clean-install smoke tests, verifies the built gem, and requests a
short-lived RubyGems credential only immediately before the push. It stores no
long-lived registry secret.

The workflow remains fail-closed until a gem owner registers
`ivankuznetsov/prdigest`, `release.yml`, and environment `release` on
RubyGems.org.
