# Independent ClawHub skill version

- Corrected both OpenClaw installation guides so only the PRDigest Ruby gem is
  pinned to `0.3.0`; the ClawHub install now resolves the current published
  skill.
- Documented that RubyGems and ClawHub maintain independent version histories,
  so a skill release does not need to reuse the gem's version number.
- Made authenticated ClawHub inspection, rather than the gem version, the
  authority for the latest verified skill publication, with exact commands and
  owner, slug, version, security, and source-content checks.
