# Decisions

- State version 1 binds progress to the configured IANA timezone and fails closed.
- Catch-up keeps the newest capped window and durably audits the skipped prefix.
- Search queries convert `[start, end)` into GitHub's inclusive whole-second range,
  then validate every returned repository and merge timestamp again.
- Optional line statistics are all-or-nothing; partial enrichment never renders.
- Telegram HTML is built from escaped semantic fragments and measured after entity
  parsing before chunks are sent.
- Delivery is at least once. A later chunk or state failure may duplicate earlier
  messages on retry rather than silently lose a day.
- Stable result data is separate from presentation; the CLI maps it to human/JSON
  output and public exit codes.
- systemd remains the only scheduler for v0.1.x; `serve` is a compatibility stub.
- Release preparation is reversible and never tags, publishes, or creates a release.
