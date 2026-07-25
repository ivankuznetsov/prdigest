# State and delivery

PRDigest separates scheduling progress from message-delivery progress. The
configured `state.path` is the date cursor; `state.delivery_path` is a directory
of per-date delivery checkpoints. When `delivery_path` is absent it defaults to
`deliveries/` beside the cursor file.

## Date cursor

Cursor JSON version 1 binds `last_digested_date` to the configured IANA
`timezone`. It can also carry a `last_skip` audit with `start_date`, `end_date`,
and `notice_pending`. Scheduled runs read and update this cursor; explicit replay
and dry-run do not. Cursor writes are atomic mode-`0600` replacements followed by
directory fsync.

## Delivery checkpoint

A real non-empty delivery opens `<delivery_path>/<date>.json` under a
nonblocking `<date>.lock`. The checkpoint uses schema
`prdigest-delivery-checkpoint`, version 1:

| Field | Role |
|---|---|
| `date`, `chat_id`, `scope` | Identity of the digest and exact ordered repository scope |
| `chunks`, `chunks_sha256` | First stored rendered payload and its integrity digest |
| `next_chunk` | Index of the next definitely-unsent chunk |
| `status` | `pending`, `completed`, or `blocked` |
| `in_flight` | Chunk index and start time persisted before an HTTP request |
| `permanent_error` | Kind, message, and failed index for a blocked checkpoint |
| `created_at`, `updated_at` | UTC checkpoint timestamps |

Reopening a date requires the same date, chat, and ordered scope. The stored
chunks are then authoritative: regenerated chunks are ignored, and their stored
digest is validated. A completed checkpoint is therefore a no-op even if the
date cursor previously failed to advance.

## Transitions and recovery

Before each request, the checkpoint records the target chunk as `in_flight`.
Definite acceptance increments `next_chunk`, clears `in_flight`, and marks the
checkpoint `completed` after the final chunk.

Telegram 429 and 5xx responses are definite rejections. They clear `in_flight`,
leave the checkpoint pending, and receive at most three attempts within one
60-second cumulative retry-wait budget. A later invocation starts from
`next_chunk`, including after retry exhaustion.

Other HTTP/API responses are permanent failures and mark the checkpoint
`blocked`. A transport exception leaves the pre-request `in_flight` marker in
place because acceptance is unknowable. Future invocations return the stored
permanent or ambiguous failure without sending. Moving a checkpoint to permit
an intentional replay is an operator reconciliation step, not an automatic
transition.

The checkpoint directory is forced to mode `0700`; JSON and lock files are
mode `0600`, and checkpoint replacements are atomic with file and directory
fsync. The per-date lock prevents duplicate delivery for one checkpoint, but
there is no global lock around date-cursor scheduling.
