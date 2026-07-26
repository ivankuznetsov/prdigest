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

Standalone prose uses the environment variable named by
`prose.api_key_env`. Never place the provider key itself in YAML, shell history,
arguments, checkpoints, fixtures, or logs. Remote provider URLs must use HTTPS;
plaintext HTTP is accepted only for exact `localhost`, IPv4 `127.0.0.0/8`, or
IPv6 `::1` loopback hosts. PRDigest rejects provider URLs with embedded
credentials, query strings, or fragments and does not include provider response
bodies in errors. Generated prose containing C0/C1 terminal controls is rejected
before stdout, checkpoints, or Telegram; tabs and newlines remain allowed.

Private pull-request titles and author names cross from GitHub into the configured
Telegram chat. Treat that chat and its members as having access to repository
metadata. PRDigest refuses non-allowlisted chat IDs before opening a connection.

`prdigest facts` writes repository names, titles, authors, URLs, merge times, and
optional statistics to stdout. The caller owns that output after the single JSON
document is emitted; avoid terminal capture, shell tracing, and logs that are
broader than the repository's audience.

OpenClaw mode sends that facts document into the configured OpenClaw execution
and model boundary so OpenClaw can write prose. Standalone `prdigest prose`
sends the same complete document plus the configured model name to the
OpenAI-compatible endpoint. Private repositories therefore require an OpenClaw
deployment or provider whose data handling, retention, and access controls are
acceptable to the operator. Neither mode is ambient: `prdigest run` and
`prdigest facts` never contact the standalone prose provider.

Pull-request fields are untrusted input. The built-in provider prompt and the
OpenClaw skill explicitly classify the facts JSON as data, never instructions,
but operators should still restrict tools and authority available to any model
processing private repository content. The OpenClaw skill must not make a second
GitHub query, deliver messages, install software silently, or print credentials.

Prose Telegram checkpoints contain generated text derived from repository facts.
They use the same secret-free mode-`0600` files and mode-`0700` directories as
deterministic delivery, under a separate `prose` namespace. Protect, retain, and
delete them as private repository metadata.

## Reporting

Report vulnerabilities privately to the maintainer address in the gem metadata.
Do not include credentials, token-bearing URLs, private PR content, config files,
state files, or unredacted journal output.

## Supported release

Security fixes target the latest published release. The build and test process
does not tag or publish releases automatically.
