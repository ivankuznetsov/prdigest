# Known gaps

- GitHub publishes no search-index freshness SLA. The 09:05 host-local timer and
  explicit replay reduce the risk but cannot prove a merge was indexed on time.
- GitHub search's 1,000-result ceiling is a hard v0.1.0 operating limit; PRDigest
  refuses incomplete/over-cap days instead of truncating.
- Concurrent scheduled invocations still have no global date-cursor lock and are
  unsupported. Per-date delivery is locked and checkpointed, so a competing
  sender cannot duplicate the same stored payload.
- A stored in-flight Telegram attempt cannot prove whether Telegram accepted the
  chunk. PRDigest parks it as ambiguous; reconciliation and any deliberate
  checkpoint move/replay remain manual operator work.
- Authenticated GitHub/Telegram smokes and the clean Ubuntu walkthrough require
  operator infrastructure and credentials. Their checklist is documented in the
  README; retain only redacted timestamp/status evidence when performed.
- Independent review is owned by the stage-6 autonomous review loop and is not
  claimed by the implementation stage.
