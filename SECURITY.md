# Security

## Credentials

PRDigest reads tokens only from environment variables. Keep `/etc/prdigest/.env`
owned by `root:root` with mode `0600`; never put tokens in YAML, command-line
arguments, fixtures, logs, or issue reports.

Use a fine-grained GitHub personal access token limited to the repositories in
`github.repos`, with read-only metadata and pull-request access. Use a dedicated
Telegram bot whose `chat_id` is the only delivery target in the allowlist. Rotate
either token immediately if it may have appeared in output, then inspect and
restrict journal retention.

Private pull-request titles and author names cross from GitHub into the configured
Telegram chat. Treat that chat and its members as having access to repository
metadata. PRDigest refuses non-allowlisted chat IDs before opening a connection.

## Reporting

Report vulnerabilities privately to the maintainer address in the gem metadata.
Do not include credentials, token-bearing URLs, private PR content, config files,
state files, or unredacted journal output.

## Supported release

Security fixes target the latest published release. The build and test process
does not tag or publish releases automatically.
