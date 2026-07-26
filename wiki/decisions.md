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
- `Collector` is the canonical facts engine. Deterministic Telegram, facts JSON,
  OpenClaw prose, and standalone provider prose must not grow independent fetch
  or ordering logic.
- `prdigest-facts` version 1 has no generation timestamp and retains nullable
  statistic fields, keeping identical inputs deterministic and absence distinct
  from zero.
- Configuration validation is capability-scoped. Facts need GitHub only;
  deterministic delivery needs GitHub and Telegram; standalone prose additionally
  needs an explicit OpenAI-compatible endpoint/model/key environment reference.
- AI is presentation over untrusted facts, never a facts source. Provider
  failures are visible with exit 7 and do not silently fall back.
- Provider-backed Telegram delivery persists final rendered prose before sending
  and replays that exact checkpoint without re-querying GitHub or the provider.
- The OpenClaw skill belongs to this repository and invokes only `prdigest facts`.
  It remains visible when the Ruby CLI is missing so setup can require
  consent; unsupported Ruby-gem installer metadata is not invented.
- systemd remains the only scheduler for v0.1.x; `serve` is a compatibility stub.
- Release preparation is reversible and never tags, publishes, or creates a release.
