# Dependencies

Runtime dependencies are Thor for the CLI surface, Octokit for GitHub REST,
Faraday Retry as part of the HTTP stack, TZInfo for IANA civil-time conversion,
and ERB because Octokit loads it on supported Ruby versions. Telegram delivery
uses Ruby's `Net::HTTP` with peer verification and no redirect handling.
Optional standalone prose also uses `Net::HTTP`, targeting the common
OpenAI-compatible `/chat/completions` contract with a bearer key named by
configuration. It adds no provider SDK dependency and is never constructed by
`facts`.

The OpenClaw integration is a text-only `SKILL.md` bundle owned by this
repository. ClawHub distributes that bundle separately from RubyGems; the bundle
contains no executable runtime and cannot install the Ruby gem through
unsupported installer metadata. The two registries have independent version
histories: installation pins the intended Ruby gem release while ClawHub
resolves its current skill unless an independently selected skill version is
required.

Minitest, Rake, and WebMock are development-only. WebMock disables external
connections for every automated test. Linux/container deployments require the
system `tzdata` database; the Alpine image installs it explicitly.

The supported Ruby matrix is 3.2, 3.3, and 3.4.
