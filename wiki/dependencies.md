# Dependencies

Runtime dependencies are Thor for the CLI surface, Octokit for GitHub REST,
Faraday Retry as part of the HTTP stack, TZInfo for IANA civil-time conversion,
and ERB because Octokit loads it on supported Ruby versions. Telegram delivery
uses Ruby's `Net::HTTP` with peer verification and no redirect handling.

Minitest, Rake, and WebMock are development-only. WebMock disables external
connections for every automated test. Linux/container deployments require the
system `tzdata` database; the Alpine image installs it explicitly.

The supported Ruby matrix is 3.2, 3.3, and 3.4.
