#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
run_id="$(date +%s)-$$"
tag="prdigest-smoke:0.1.1-$run_id"
volume="prdigest-smoke-$run_id"
smoke_config=$(mktemp)
smoke_result=$(mktemp)
trap 'rm -f "$smoke_config" "$smoke_result"; docker volume rm -f "$volume" >/dev/null 2>&1 || true; docker image rm -f "$tag" >/dev/null 2>&1 || true' EXIT HUP INT TERM

run_and_show() {
  output=$1
  shift
  if "$@" >"$output"; then
    cat "$output"
  else
    status=$?
    cat "$output"
    return "$status"
  fi
}

if run_and_show "$smoke_result" \
  sh -c 'printf "%s\n" run-and-show-failure-sentinel; exit 7'; then
  echo "run_and_show unexpectedly accepted a failing command" >&2
  exit 1
else
  status=$?
fi
test "$status" -eq 7
grep -Fq 'run-and-show-failure-sentinel' "$smoke_result"

sed -e 's/line_stats: true/line_stats: false/' -e 's/send_empty: true/send_empty: false/' \
  "$root/configs/config.example.yml" > "$smoke_config"
chmod 0644 "$smoke_config"

docker build -t "$tag" "$root"
run_and_show "$smoke_result" docker run --rm --entrypoint id "$tag" -u
grep -Eq '^[1-9][0-9]*$' "$smoke_result"
docker run --rm --entrypoint ruby "$tag" -rtzinfo -e 'abort unless TZInfo::Timezone.get("Europe/London")'

docker volume create "$volume" >/dev/null
docker run --rm --user root --entrypoint sh -v "$volume:/var/lib/prdigest" "$tag" \
  -c 'chown -R prdigest:prdigest /var/lib/prdigest && chmod 0700 /var/lib/prdigest'

run_and_show "$smoke_result" docker run --rm \
  -e GITHUB_TOKEN=synthetic-smoke-token \
  -e RUBYOPT=-r/opt/prdigest/offline_smoke_stubs.rb \
  -v "$smoke_config:/etc/prdigest/config.yml:ro" \
  -v "$root/test/support/offline_smoke_stubs.rb:/opt/prdigest/offline_smoke_stubs.rb:ro" \
  -v "$volume:/var/lib/prdigest" \
  "$tag" run --config /etc/prdigest/config.yml --date 2026-01-15 --dry-run --json

grep -Fq '"status":"dry_run"' "$smoke_result"
grep -Fq 'Synthetic packaged Time result' "$smoke_result"

docker run --rm --entrypoint sh -v "$volume:/var/lib/prdigest" "$tag" -c \
  'test ! -e /var/lib/prdigest/state.json &&
   test ! -e /var/lib/prdigest/deliveries'

run_and_show "$smoke_result" docker run --rm \
  -e GITHUB_TOKEN=synthetic-smoke-token \
  -e TELEGRAM_BOT_TOKEN=synthetic-smoke-token \
  -e PRDIGEST_SMOKE_EMPTY=1 \
  -e RUBYOPT=-r/opt/prdigest/offline_smoke_stubs.rb \
  -v "$smoke_config:/etc/prdigest/config.yml:ro" \
  -v "$root/test/support/offline_smoke_stubs.rb:/opt/prdigest/offline_smoke_stubs.rb:ro" \
  -v "$volume:/var/lib/prdigest" \
  "$tag" run --config /etc/prdigest/config.yml --json

grep -Fq '"status":"success"' "$smoke_result"

docker run --rm --entrypoint sh -v "$volume:/var/lib/prdigest" "$tag" -c \
  'test -f /var/lib/prdigest/state.json &&
   test "$(stat -c %a /var/lib/prdigest/state.json)" = 600 &&
   test "$(stat -c %u /var/lib/prdigest/state.json)" = "$(id -u)"'
