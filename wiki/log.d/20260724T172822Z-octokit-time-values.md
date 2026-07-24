# 2026-07-24 — Accept Octokit timestamp objects

GitHub search mapping now accepts both ISO-8601 strings and the `Time` objects
that Octokit materializes in real responses. Repository and half-open UTC-window
validation still run against the normalized UTC timestamp.

The regression test uses the production-shaped `Time` value so offline fixtures
cannot hide this adapter boundary again.
