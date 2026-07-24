#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

sed "s#/usr/local/bin/prdigest#$root/exe/prdigest#" \
  "$root/scripts/systemd/prdigest.service" >"$tmp/prdigest.service"
cp "$root/scripts/systemd/prdigest.timer" "$tmp/prdigest.timer"
systemd-analyze verify "$tmp/prdigest.service" "$tmp/prdigest.timer"
