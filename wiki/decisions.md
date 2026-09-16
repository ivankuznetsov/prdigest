# Decisions

- Search queries convert `[start, end)` into GitHub's inclusive whole-second range,
  then validate every returned repository and merge timestamp again.
- Optional line statistics are all-or-nothing; partial enrichment never renders.
- `Collector` is the canonical facts engine. Facts JSON, OpenClaw prose, and
  standalone provider prose must not grow independent fetch or ordering logic.
- `prdigest-facts` version 1 has no generation timestamp and retains nullable
  statistic fields, keeping identical inputs deterministic and absence distinct
  from zero.
- Configuration validation is capability-scoped. Facts need GitHub only;
  standalone prose additionally needs an explicit OpenAI-compatible
  endpoint/model/key environment reference, and delivery additionally needs an
  allowlisted Telegram chat.
- AI is presentation over untrusted facts, never a facts source. Provider
  failures are visible with exit 7 and do not silently fall back.
- Pull-request prose receives bounded descriptions and relevant file patches
  from the canonical collector. Every bound is explicit in facts metadata;
  generators must never claim that supplied evidence is a complete diff.
- `Document.generate(facts:, generator:)` is the provider-free reusable prose
  interface. The CLI's configured provider and Telegram delivery are adapters
  around it, so an embedding runtime can use the same prompt without an API key
  or delivery side effect.
- The shared writing contract returns one concise editorial Markdown document:
  a dated title, grouped user-facing themes, and full clickable PR links.
- Prompt limits retain every PR reference, title, and description, trim patch
  evidence first with explicit metadata, and fail clearly if metadata alone is
  too large.
- Remote provider credentials and facts cross only HTTPS; plaintext HTTP is
  restricted to exact loopback hosts. Generated terminal controls are rejected
  before prose can reach stdout, checkpoints, or Telegram.
- Provider-backed Telegram delivery persists final plain-text chunks before
  sending and replays that exact checkpoint without re-querying GitHub or the
  provider. Telegram `parse_mode` is intentionally unset.
- The OpenClaw skill belongs to this repository and invokes only `prdigest facts`.
  It remains visible when the Ruby CLI is missing so setup can require
  consent; unsupported Ruby-gem installer metadata is not invented.
- The public CLI contains only `facts`, `prose`, and `version`. The deterministic
  `run` renderer, date cursor, catch-up engine, result envelope, and `serve` stub
  were removed rather than deprecated.
- systemd remains the daily scheduler and invokes `prose --deliver`.
- Release preparation is reversible and never tags, publishes, or creates a release.
- RubyGems publication has one explicit authority: the exact-tag `release.yml`
  workflow. It verifies tag/version identity and tests the tagged package before
  exchanging GitHub OIDC for a short-lived trusted-publisher credential.
