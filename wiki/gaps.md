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
- Independent review is owned by the stage-6 autonomous review loop and is not
  claimed by the implementation stage.
