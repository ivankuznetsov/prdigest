#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
ruby_bin=$(command -v ruby)
ruby_dir=$(dirname -- "$ruby_bin")
smoke_path="$tmp/bin:$ruby_dir:/usr/bin:/bin"

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

if run_and_show "$tmp/run-and-show-failure.out" \
  sh -c 'printf "%s\n" run-and-show-failure-sentinel; exit 7'; then
  echo "run_and_show unexpectedly accepted a failing command" >&2
  exit 1
else
  status=$?
fi
test "$status" -eq 7
grep -Fq 'run-and-show-failure-sentinel' "$tmp/run-and-show-failure.out"

gem build "$root/prdigest.gemspec" --output "$tmp/prdigest.gem"
GEM_HOME="$tmp/gems" GEM_PATH="$tmp/gems" \
  gem install "$tmp/prdigest.gem" --install-dir "$tmp/gems" --bindir "$tmp/bin" --no-document

mkdir -p "$tmp/config"
mkdir -p "$tmp/home"
cp "$root/configs/config.example.yml" "$tmp/config/config.yml"
cd "$tmp"

run_and_show "$tmp/version.out" env -i \
  HOME="$tmp/home" PATH="$smoke_path" \
  GEM_HOME="$tmp/gems" GEM_PATH="$tmp/gems" RUBYOPT= RUBYLIB= \
  prdigest version
grep -Fq "prdigest 0.1.1" "$tmp/version.out"

env -i HOME="$tmp/home" PATH="$smoke_path" \
  GEM_HOME="$tmp/gems" GEM_PATH="$tmp/gems" RUBYOPT= RUBYLIB= \
  "$ruby_bin" -rprdigest -e '
    feature = $LOADED_FEATURES.find { |path| path.end_with?("/prdigest.rb") }
    gem_root = "#{File.realpath(ENV.fetch("GEM_HOME"))}#{File::SEPARATOR}"
    abort "prdigest loaded outside isolated GEM_HOME: #{feature}" unless
      feature && File.realpath(feature).start_with?(gem_root)
  '

run_and_show "$tmp/result.json" env -i \
  HOME="$tmp/home" PATH="$smoke_path" \
  GEM_HOME="$tmp/gems" GEM_PATH="$tmp/gems" \
  GITHUB_TOKEN=synthetic-smoke-token \
  RUBYOPT="-r$root/test/support/offline_smoke_stubs.rb" RUBYLIB= \
  prdigest run --config "$tmp/config/config.yml" --date 2026-01-15 --dry-run --json

grep -Fq '"status":"dry_run"' "$tmp/result.json"
grep -Fq 'Synthetic packaged Time result' "$tmp/result.json"

run_and_show "$tmp/facts.json" env -i \
  HOME="$tmp/home" PATH="$smoke_path" \
  GEM_HOME="$tmp/gems" GEM_PATH="$tmp/gems" \
  GITHUB_TOKEN=synthetic-smoke-token \
  RUBYOPT="-r$root/test/support/offline_smoke_stubs.rb" RUBYLIB= \
  prdigest facts --config "$tmp/config/config.yml" --date 2026-01-15

grep -Fq '"schema":"prdigest-facts"' "$tmp/facts.json"
grep -Fq '"schema_version":1' "$tmp/facts.json"
grep -Fq '"status":"success"' "$tmp/facts.json"
grep -Fq 'Synthetic packaged Time result' "$tmp/facts.json"
