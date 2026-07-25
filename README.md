# PRDigest

PRDigest is a deterministic Ruby oneshot that sends a daily digest of merged
GitHub pull requests to one allowlisted Telegram chat. It is designed for a
single operator on a small VPS: repositories are explicit, secrets stay in the
environment, and a hardened systemd timer owns scheduling.

## Requirements and installation

- Ruby 3.2–3.4 and `tzdata`
- a fine-grained GitHub token with read-only access to the listed repositories
- a dedicated Telegram bot and one destination chat ID

For development:

```sh
bundle install
bundle exec prdigest version
GITHUB_TOKEN=... bundle exec prdigest run --config configs/config.example.yml --dry-run
```

To build and install the prepared gem without publishing it:

```sh
gem build prdigest.gemspec
gem install prdigest-0.1.1.gem
prdigest version
```

## Configuration and secrets

Configuration lookup is strict: an explicit `--config PATH` wins, then
`PRDIGEST_CONFIG`, then an existing `/etc/prdigest/config.yml`. PRDigest refuses
to run when none exists. See `configs/config.example.yml` for every setting.

```yaml
timezone: Europe/London
schedule:
  max_catchup_days: 7
github:
  token_env: GITHUB_TOKEN
  repos:
    - owner/repo-one
    - owner/repo-two
telegram:
  token_env: TELEGRAM_BOT_TOKEN
  chat_id_allowlist: [-1001234567890]
  chat_id: -1001234567890
digest:
  line_stats: true
  send_empty: true
  empty_message: "Merged PR digest — {date}\nTotal: 0 PRs"
state:
  path: /var/lib/prdigest/state.json
  delivery_path: /var/lib/prdigest/deliveries
```

Repository order controls digest order. `max_catchup_days` must be `1..30`.
`chat_id` must appear in the non-empty allowlist; extra allowlisted IDs are
accepted for schema compatibility but v0.1.x sends only to `chat_id`. Token
values belong in environment variables, never YAML.

## Commands and results

```sh
prdigest run [--config PATH] [--date YYYY-MM-DD] [--dry-run] [--json] [--repo OWNER/NAME ...]
prdigest serve
prdigest version
```

An ordinary `run` reads state, processes owed dates oldest-first, and writes
state after each settled day. `--date` replays exactly that local date and never
reads or writes state. `--dry-run` previews the explicit date or yesterday,
requires GitHub access, and constructs neither state nor Telegram delivery.
`serve` remains a compatibility stub; use the supplied timer.
Repeatable `--repo` values replace the configured repository list for that run.
They use the same strict `owner/name` validation and deterministic order as the
configuration, which lets callers such as Hive supply their registered projects
without owning a second digest implementation.

`--json` emits a versioned `prdigest-result` document with `status`, `mode`, `requested_days`,
`settled_days`, `skipped_days`, `failed_date`, `remaining_days`, nullable
`error`, dry-run `chunks`, and nullable structured `delivery` progress.
`delivery` reports `accepted_chunks`, `total_chunks`, `status`, and, on failure,
`failed_chunk`. Modes are `scheduled` and
`explicit_date_replay`; statuses are `success`, `dry_run`, `failure`, and
`partial_failure`.

| Exit | Meaning |
|---:|---|
| 0 | completed or dry-run |
| 1 | unexpected or render failure |
| 2 | CLI/configuration refusal |
| 3 | GitHub failure |
| 4 | Telegram failure |
| 5 | state failure |
| 6 | failure after earlier durable progress |

## Delivery and state semantics

Each local day is converted to independent UTC midnight boundaries, including
DST gaps and repeats. GitHub results are completely fetched and rendered before
the first Telegram message. A day is settled only after every chunk succeeds,
an enabled empty message succeeds, or an empty message is intentionally
suppressed.

Before sending, PRDigest stores the complete rendered chunk list in
`state.delivery_path`. It marks one chunk in flight before each request and
advances `next_chunk` only after Telegram definitely accepts it. A definite
429/5xx rejection receives at most three attempts; a later invocation resumes
the original rendered payload at the next unsent chunk. If the date cursor write
fails after complete delivery, the retry observes the completed delivery
checkpoint and sends nothing before repairing the cursor.

Telegram 400/invalid-response failures are permanent. Transport failures are
ambiguous because Telegram might have accepted the request before the
connection failed. Both cases remain parked and never replay automatically.
Inspect the checkpoint and Telegram chat, reconcile the uncertain chunk, then
move the checkpoint aside only when an intentional operator replay is safe.
Changing the chat or repository scope for an existing date also fails closed.
Explicit `--date` uses this same safety ledger, so a completed date is a no-op
unless its checkpoint is deliberately archived first.

State is secret-free JSON version 1:

```json
{"version":1,"timezone":"Europe/London","last_digested_date":"2026-07-15"}
```

It may include a `last_skip` audit with `start_date`, `end_date`, and
`notice_pending`. Writes use an atomic mode-`0600` replacement and directory
fsync. Delivery directories are mode `0700`; delivery files and locks are mode
`0600`, and a per-date lock prevents concurrent sends for the same checkpoint.
Missing state means first run and requests yesterday only. Malformed,
future, unsupported, unreadable, or timezone-mismatched state fails closed with
exit 5.

When backlog exceeds the cap, PRDigest durably skips the oldest prefix and
processes only the newest window. That loss is intentional and reported. For a
timezone migration, stop the timer, preserve the old state for audit, move it
aside, change the configured timezone, use explicit replay for any required
dates, then restart the timer. Never silently edit a corrupt checkpoint; inspect
and repair ownership/JSON or restore a known-good copy first.

GitHub does not publish a search-index freshness guarantee. Keep the host
timezone equal to the configured digest timezone; the supplied 09:05 timer then
leaves about nine hours after local midnight. If a later audit finds a delayed
merge, use `--date YYYY-MM-DD` to replay it.

## systemd deployment

On Ubuntu, install Ruby, `tzdata`, the gem, and then:

```sh
sudo useradd --system --home /nonexistent --shell /usr/sbin/nologin prdigest
sudo install -d -o root -g prdigest -m 0750 /etc/prdigest
sudo install -o root -g prdigest -m 0640 configs/config.example.yml /etc/prdigest/config.yml
sudo install -o root -g root -m 0600 .env.example /etc/prdigest/.env
sudo install -o root -g root -m 0644 scripts/systemd/prdigest.service /etc/systemd/system/
sudo install -o root -g root -m 0644 scripts/systemd/prdigest.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start prdigest.service
sudo systemctl enable --now prdigest.timer
```

Edit the installed config and environment file before starting. systemd creates
`/var/lib/prdigest` as `prdigest:prdigest` mode `0700`; state files are `0600`.
Inspect with `systemctl status prdigest.service`, `systemctl list-timers
prdigest.timer`, and `journalctl -u prdigest.service`. Test a missed-day catch-up
by stopping the timer for a day, then starting the service. Journal output can
contain repository/date context, so restrict journal group membership and
retention.

Rollback by stopping the timer, installing the prior gem/image, restoring the
matching config and a known-good state backup, and restarting. Replay omitted
dates explicitly; do not move a checkpoint forward by hand.

## Container

The Alpine image includes `tzdata` and runs as the unprivileged `prdigest` user.
Initialize mounted ownership with the image before normal use:

```sh
docker build -t prdigest:0.1.1 .
docker volume create prdigest-state
docker run --rm --user root --entrypoint sh -v prdigest-state:/var/lib/prdigest prdigest:0.1.1 \
  -c 'chown -R prdigest:prdigest /var/lib/prdigest && chmod 0700 /var/lib/prdigest'
docker run --rm --env-file /etc/prdigest/.env \
  -v /etc/prdigest/config.yml:/etc/prdigest/config.yml:ro \
  -v prdigest-state:/var/lib/prdigest prdigest:0.1.1
```

## Verification and troubleshooting

`bundle exec rake test` is fully offline. Release preparation also supplies
`test/smoke/gem_install.sh`, `test/smoke/docker.sh`, and
`test/smoke/systemd.sh`. Live GitHub boundary and Telegram allowlist smokes are
manual gates: retain timestamps and pass/fail only, never credentials, response
bodies, message text, or private titles.

- Exit 2: check config discovery, YAML, timezone, cap, chat allowlist, and env.
- Exit 3: check repository access, rate/search limits, and replay later.
- Exit 4: inspect `error.kind` and `delivery`. Retry ordinary `telegram` failures;
  reconcile `telegram_ambiguous`, `telegram_permanent`, and
  `delivery_checkpoint_permanent` before moving any checkpoint.
- Exit 5: check `/var/lib/prdigest`, mode/owner, JSON version, date, and timezone.
- Exit 6: earlier dates or a skipped prefix are durable; inspect the result before retry.

Concurrent scheduled runs remain unsupported because date-cursor scheduling is
single-owner. Delivery itself takes a nonblocking per-date lock, so a competing
sender fails instead of duplicating the same payload. The systemd oneshot is the
normal run coordination mechanism.

See [SECURITY.md](SECURITY.md) for token scope, rotation, and private-data flow.

## Non-goals

v0.1.x has no built-in Hive configuration discovery, LLM content, web UI,
interactive bot commands,
multi-chat routing, organization discovery, non-GitHub forge support, or
long-running scheduler. The build and test process never tags or publishes
automatically.

## License

MIT
