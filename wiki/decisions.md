# Decisions

- State version 1 binds progress to the configured IANA timezone and fails closed.
- Catch-up keeps the newest capped window and durably audits the skipped prefix.
- Search queries convert `[start, end)` into GitHub's inclusive whole-second range,
  then validate every returned repository and merge timestamp again.
- Optional line statistics are all-or-nothing; partial enrichment never renders.
- Telegram HTML is built from escaped semantic fragments and measured after entity
  parsing before chunks are sent.
- Delivery checkpoints preserve the first rendered chunk list for each date and
  advance only after definite Telegram acceptance, so retries do not resend the
  accepted prefix.
- Ambiguous transport outcomes and permanent Telegram responses fail closed for
  operator reconciliation; only definite 429/5xx rejection is retried.
- Repeatable `--repo owner/name` inputs replace the configured repository scope
  after the same strict validation and case-insensitive de-duplication.
- Stable result data is separate from presentation. The public JSON envelope is
  schema-versioned, while the CLI maps results to human output and stable exit
  codes.
- systemd remains the only scheduler for v0.1.0; `serve` is a compatibility stub.
- Release preparation is reversible and never tags, publishes, or creates a release.
