#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

gem build "$root/prdigest.gemspec" --output "$tmp/prdigest.gem"
GEM_HOME="$tmp/gems" GEM_PATH="$tmp/gems" \
  gem install "$tmp/prdigest.gem" --install-dir "$tmp/gems" --bindir "$tmp/bin" --no-document

PATH="$tmp/bin:$PATH" GEM_HOME="$tmp/gems" GEM_PATH="$tmp/gems" \
  prdigest version | grep -F "prdigest 0.1.0"

mkdir -p "$tmp/config"
cp "$root/configs/config.example.yml" "$tmp/config/config.yml"
GITHUB_TOKEN=synthetic-smoke-token \
  RUBYOPT="-r$root/test/support/offline_smoke_stubs.rb" \
  PATH="$tmp/bin:$PATH" \
  GEM_HOME="$tmp/gems" \
  GEM_PATH="$tmp/gems" \
  prdigest run --config "$tmp/config/config.yml" --date 2026-01-15 --dry-run --json \
  | grep -F '"status":"dry_run"'
