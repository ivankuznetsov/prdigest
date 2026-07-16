#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tag="prdigest-smoke:0.1.0"
volume="prdigest-smoke-$$"
trap 'docker volume rm -f "$volume" >/dev/null 2>&1 || true; docker image rm -f "$tag" >/dev/null 2>&1 || true' EXIT HUP INT TERM

docker build -t "$tag" "$root"
test "$(docker run --rm --entrypoint id "$tag" -u)" != "0"
docker run --rm --entrypoint ruby "$tag" -rtzinfo -e 'abort unless TZInfo::Timezone.get("Europe/London")'

docker volume create "$volume" >/dev/null
docker run --rm --user root --entrypoint sh -v "$volume:/var/lib/prdigest" "$tag" \
  -c 'chown -R prdigest:prdigest /var/lib/prdigest && chmod 0700 /var/lib/prdigest'
docker run --rm --entrypoint sh -v "$volume:/var/lib/prdigest" "$tag" -c 'touch /var/lib/prdigest/write-proof'

docker run --rm \
  -e GITHUB_TOKEN=synthetic-smoke-token \
  -e RUBYOPT=-r/opt/prdigest/offline_smoke_stubs.rb \
  -v "$root/configs/config.example.yml:/etc/prdigest/config.yml:ro" \
  -v "$root/test/support/offline_smoke_stubs.rb:/opt/prdigest/offline_smoke_stubs.rb:ro" \
  "$tag" run --config /etc/prdigest/config.yml --date 2026-01-15 --dry-run --json \
  | grep -F '"status":"dry_run"'
