#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tag="prdigest-smoke:0.1.0"
volume="prdigest-smoke-$$"
smoke_config=$(mktemp)
trap 'rm -f "$smoke_config"; docker volume rm -f "$volume" >/dev/null 2>&1 || true; docker image rm -f "$tag" >/dev/null 2>&1 || true' EXIT HUP INT TERM

sed -e 's/line_stats: true/line_stats: false/' -e 's/send_empty: true/send_empty: false/' \
  "$root/configs/config.example.yml" > "$smoke_config"
chmod 0644 "$smoke_config"

docker build -t "$tag" "$root"
test "$(docker run --rm --entrypoint id "$tag" -u)" != "0"
docker run --rm --entrypoint ruby "$tag" -rtzinfo -e 'abort unless TZInfo::Timezone.get("Europe/London")'

docker volume create "$volume" >/dev/null
docker run --rm --user root --entrypoint sh -v "$volume:/var/lib/prdigest" "$tag" \
  -c 'chown -R prdigest:prdigest /var/lib/prdigest && chmod 0700 /var/lib/prdigest'

docker run --rm \
  -e GITHUB_TOKEN=synthetic-smoke-token \
  -e TELEGRAM_BOT_TOKEN=synthetic-smoke-token \
  -e RUBYOPT=-r/opt/prdigest/offline_smoke_stubs.rb \
  -v "$smoke_config:/etc/prdigest/config.yml:ro" \
  -v "$root/test/support/offline_smoke_stubs.rb:/opt/prdigest/offline_smoke_stubs.rb:ro" \
  -v "$volume:/var/lib/prdigest" \
  "$tag" run --config /etc/prdigest/config.yml --json \
  | grep -F '"status":"success"'

docker run --rm --entrypoint sh -v "$volume:/var/lib/prdigest" "$tag" -c \
  'test -f /var/lib/prdigest/state.json &&
   test "$(stat -c %a /var/lib/prdigest/state.json)" = 600 &&
   test "$(stat -c %u /var/lib/prdigest/state.json)" = "$(id -u)"'
