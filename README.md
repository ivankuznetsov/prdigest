# prdigest

Standalone **daily merged-PR digests** for any GitHub repos you list.

Ruby CLI gem. Put it on a VPS with:

1. repo list  
2. GitHub token  
3. Telegram bot + allowlisted chats  

…and it sends digests like Hive’s merged-PR report **without installing Hive**.

## Stack

- **Ruby 3.2+**
- **Thor** CLI
- **Octokit** for GitHub (no local `gh` required on the VPS)
- plain Telegram Bot API `sendMessage`
- YAML config + env secrets
- **v1 schedule:** systemd timer + `prdigest run` (boring, reliable)
- optional later: long-running `serve`

## Install (dev)

```bash
git clone https://github.com/ivankuznetsov/prdigest
cd prdigest
bundle install
bundle exec prdigest version
bundle exec prdigest run --dry-run --config configs/config.example.yml
```

## Config

See `configs/config.example.yml`.

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

Tokens in env only: `GITHUB_TOKEN`, `TELEGRAM_BOT_TOKEN`.

## Commands

```bash
prdigest run [--config PATH] [--date YYYY-MM-DD] [--dry-run] [--json]
prdigest serve   # deferred; use systemd timer for v1
prdigest version
```

## VPS sketch

```bash
# install ruby + gem or clone + bundle
cp configs/config.example.yml /etc/prdigest/config.yml
cp .env.example /etc/prdigest/.env
# edit repos + chats; put tokens in .env

# oneshot + timer
cp scripts/systemd/prdigest.service /etc/systemd/system/
cp scripts/systemd/prdigest.timer /etc/systemd/system/
systemctl enable --now prdigest.timer
```

## Non-goals (v1)

- No Hive dependency / registered projects
- No shipped-task narration
- No org-wide auto-discovery (explicit repo list only)

## Relationship to Hive

Hive keeps an integrated digest for Hive users.  
`prdigest` is the portable multi-repo extract for any GitHub repos on a VPS.

## Status

Ruby scaffold + config validation. GitHub fetch / Telegram send / line stats next.

## License

MIT
