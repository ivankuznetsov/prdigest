# prdigest

Standalone **daily merged-PR digests** for any GitHub repos you list.

Put it on a VPS, give it a GitHub token + Telegram bot + allowlisted chats, and it will send a digest like Hive’s merged-PR report — **without installing Hive**.

## What you get

- Multi-repo scan (`owner/name` list in config)
- One message per local day (timezone-aware)
- Grouped by repo: PR title, link, author
- Optional day line stats: `Lines +X/-Y · PRs N · Commits M` (best-effort GitHub stats)
- Telegram delivery with **chat allowlist** (refuse send outside allowlist)
- Daemon/cron mode with catch-up after downtime
- Open source, single binary, no Hive dependency

## Non-goals (v1)

- Not a Hive task/shipped-task digest
- Not a full agent workflow engine
- No auto-discovery of “all your GitHub orgs” (explicit repo list only)

## Quick start

```bash
# build
go build -o bin/prdigest ./cmd/prdigest

# config
cp configs/config.example.yml /etc/prdigest/config.yml
cp .env.example /etc/prdigest/.env
# edit repos, chat_id, allowlist; put tokens in env

# one-shot (yesterday in configured timezone)
export $(grep -v '^#' /etc/prdigest/.env | xargs)
./bin/prdigest run --config /etc/prdigest/config.yml

# specific day, dry-run
./bin/prdigest run --date 2026-07-14 --dry-run

# long-running scheduler
./bin/prdigest serve --config /etc/prdigest/config.yml
```

## Config sketch

```yaml
timezone: Europe/London
github:
  repos:
    - ivankuznetsov/hive
    - ivankuznetsov/agent-plugins
telegram:
  chat_id_allowlist: [-1003827075639]
  chat_id: -1003827075639
digest:
  line_stats: true
  send_empty: true
```

Tokens stay in env (`GITHUB_TOKEN`, `TELEGRAM_BOT_TOKEN`), not in the yaml.

## Why this exists

Hive’s `hive digest --source merged-prs` is great when you already run Hive. Many teams want the **same report** on a cheap VPS with only:

1. repo list  
2. GitHub key  
3. Telegram bot + allowed chats  

`prdigest` is that extract: portable, boring, open source.

## Relationship to Hive

| | Hive digest | prdigest |
|---|---|---|
| Depends on Hive projects / worktrees | yes (registered projects) | no |
| Repo list | auto from Hive registry or `--repo` | config file only |
| Shipped-task narration | opt-in `--source shipped` | out of scope |
| Deploy | with Hive daemon | any VPS / systemd / Docker |

Hive may keep a richer integrated digest; this project is the **standalone multi-repo** product.

## Status

Scaffold / design in progress. Implementation tracked as an architecture + coding task.

## License

MIT
