# Rate-limit retries wait past the reset

Hive's daily-digest backfill (18 repositories, consecutive days) exhausted
GitHub's 30-per-minute search limit. The 403 `TooManyRequests` carried
`X-RateLimit-Reset` 45 seconds out; after sleeping exactly that long the retry
still saw `remaining=0` with a reset of "now", computed a zero wait, and burned
the last attempt in the same second ("GitHub request retries exhausted").

`GitHub#retry_delay` now adds `RATE_LIMIT_RESET_BUFFER` (2s) to reset-derived
waits, every retry waits at least 1s, and rate-limited requests allow
`MAX_RATE_LIMIT_ATTEMPTS` (5); server/transport failures keep `MAX_ATTEMPTS`
(3). The 60-second retry-delay ceiling is unchanged. Verified live with a
three-day burst: one 47s wait, all days collected.
