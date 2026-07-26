# Known gaps

- GitHub publishes no search-index freshness SLA. The 09:05 host-local timer and
  explicit replay reduce the risk but cannot prove a merge was indexed on time.
- GitHub search's 1,000-result ceiling is a hard v0.1.x operating limit; PRDigest
  refuses incomplete/over-cap days instead of truncating.
- Concurrent scheduled invocations still have no global date-cursor lock and are
  unsupported. Per-date delivery is locked and checkpointed, so a competing
  sender cannot duplicate the same stored payload.
- Ambiguous Telegram transport outcomes require operator reconciliation. PRDigest
  deliberately does not guess whether Telegram accepted an in-flight chunk.
- Authenticated GitHub/Telegram smokes and the clean Ubuntu walkthrough require
  operator infrastructure and credentials. Their checklist is documented in the
  README; retain only redacted timestamp/status evidence when performed.
- The OpenClaw skill is ClawHub-ready source, not a confirmed live listing.
  Publication requires a separate explicit release request and version direction;
  exact-version inspection, a clean install comparison, and an authenticated
  OpenClaw invocation remain unperformed.
- Live OpenAI-compatible provider behavior is not claimed by the offline suite.
  An authorized smoke still needs to prove one real endpoint/model and verify
  that retained evidence contains no key, private facts, request body, provider
  response body, or generated prose.
- A provider request can complete before safe rendering or checkpoint persistence.
  If either later step fails, an operator retry can invoke and bill the provider
  again because no replayable payload exists yet.
- Provider response size is not capped before JSON parsing; endpoint selection
  and infrastructure limits remain part of the operator trust boundary.
- Independent review is owned by the stage-6 autonomous review loop and is not
  claimed by the implementation stage.
