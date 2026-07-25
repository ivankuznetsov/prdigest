# Interfaces

## Commands

```text
prdigest run [--config PATH] [--date YYYY-MM-DD] [--repo owner/name ...] [--dry-run] [--json]
prdigest serve
prdigest version
```

`run` without `--date` is scheduled mode and uses the date cursor. `--date`
selects one strict ISO date and bypasses that cursor, while a real send still
uses the per-date delivery checkpoint. `--dry-run` renders either the explicit
date or yesterday without constructing cursor state, delivery state, or
Telegram. `serve` is a compatibility stub; systemd owns scheduling.

One or more `--repo` or `--repo=...` options replace the configured repository
list for that invocation. Each value must contain exactly two non-empty
`owner/name` segments made from letters, digits, `_`, `.`, or `-`; `.` and `..`
segments are rejected. Values are stripped and de-duplicated case-insensitively,
preserving the first spelling and input order. The config is still loaded and
validated before the override is applied.

## JSON result contract

`--json` emits one `prdigest-result` schema-version-1 document. `Result#to_h`
always contains:

| Field | Meaning |
|---|---|
| `schema`, `schema_version` | `"prdigest-result"` and `1` |
| `status` | `success`, `dry_run`, `failure`, or `partial_failure` |
| `mode` | `scheduled` or `explicit_date_replay` |
| `requested_days` | Dates selected for this call |
| `settled_days` | Dates durably settled before the result |
| `skipped_days` | Dates intentionally skipped by capped catch-up |
| `failed_date` | Current failed date, or `null` |
| `remaining_days` | Failed and later requested dates not settled |
| `error` | `{kind, message}` or `null` |
| `chunks` | Rendered dry-run chunks; real sends leave this empty |
| `delivery` | Most recent delivery progress, or `null` |

When present, `delivery` has `accepted_chunks`, `total_chunks`, and checkpoint
`status` (`pending`, `completed`, or `blocked`). Failures that identify a chunk
also include `failed_chunk`. The envelope reports one delivery snapshot rather
than a per-date delivery history.

## Exit contract

| Exit | Result |
|---:|---|
| 0 | `success` or `dry_run` |
| 1 | Render, internal, or otherwise unmapped failure |
| 2 | CLI/configuration refusal |
| 3 | GitHub failure |
| 4 | Telegram refusal/failure, ambiguous or permanent outcome, or delivery-checkpoint conflict |
| 5 | Cursor or checkpoint persistence/access failure |
| 6 | Any failure after earlier dates were settled or skipped |

Exit 6 is driven by durable earlier progress and takes precedence over the
underlying failure category. Telegram and checkpoint detail remains available
in `error.kind` and `delivery`.
