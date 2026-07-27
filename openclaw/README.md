# PRDigest OpenClaw skill

PRDigest owns one published OpenClaw skill. Its canonical local source is
[`skills/prdigest/SKILL.md`](skills/prdigest/SKILL.md); the bundle contains no
Ruby runtime, executable, credentials, or configuration.

The skill invokes only the versioned `prdigest facts` boundary. OpenClaw writes
the prose itself from that document. It does not invoke PRDigest's provider or
Telegram paths, or query GitHub directly.

The coordinated source release is `0.3.0`. Its
[`@ivankuznetsov/prdigest`](https://clawhub.ai/ivankuznetsov/skills/prdigest)
ClawHub listing is published under **Development**.

## Installation boundary

The Ruby CLI and ClawHub skill are separate installs. The manual commands are:

```sh
gem install prdigest -v 0.3.0
openclaw skills install @ivankuznetsov/prdigest
```

Or paste this prompt into an OpenClaw chat:

```text
Install PRDigest 0.3.0 in the same user/runtime context as OpenClaw with
`gem install prdigest -v 0.3.0`, then install the ClawHub skill with
`openclaw skills install @ivankuznetsov/prdigest`. This message explicitly
authorizes those two installs and only the PATH adjustment needed to make the
installed `prdigest` executable visible to the OpenClaw runtime. Do not create
PRDigest configuration files, store credentials, enable Telegram delivery, or
install a scheduler. First verify Ruby 3.2 or newer is available; if it is not,
stop and report the exact blocker instead of changing system packages. After
installation, run `prdigest version`, confirm that OpenClaw can discover the
installed PRDigest skill, and report the installed paths and versions without
exposing environment variables or tokens.
```

The skill remains discoverable when the Ruby CLI is absent, but it never
installs the gem silently. Install and configure the PRDigest CLI separately,
with explicit user approval for any user-global or system-global change.

## Local verification

Review the committed skill at `openclaw/skills/prdigest/SKILL.md`, then run the
repository tests:

```sh
bundle exec ruby -Itest test/openclaw_skill_test.rb
bundle exec rake test
```

Authenticated ClawHub inspection and a clean temporary installation are release
proof, not local implementation proof.

## Publish checklist

Publishing a future version is a release action. Do not run any publish
command—including a dry-run—without a separate explicit release request and
version direction. A dry-run can still select default version metadata even
though it does not upload the skill.

Only after that authorization:

1. Confirm the requested immutable skill version and the reviewed commit.
2. Confirm a released PRDigest gem containing `prdigest facts` is installable.
3. Run the full offline suite and packaged-gem smoke on the exact commit.
4. Authenticate with `clawhub login` and confirm the owner with
   `clawhub whoami`.
5. Publish exactly the absolute `openclaw/skills/prdigest` directory with
   `clawhub skill publish <absolute-path>` and the separately authorized owner,
   slug, and version. Do not publish the parent `openclaw` directory.
6. Wait until the exact version is inspectable, install
   `@ivankuznetsov/prdigest` into a clean temporary workspace, and compare its
   `SKILL.md` byte-for-byte with the reviewed source.
7. Run an authenticated OpenClaw smoke that discovers the skill and produces a
   bounded digest from a safe test repository without exposing facts or
   credentials in retained logs.

Until those checks pass for a future version, continue to identify `0.3.0` as
the latest verified publication rather than claiming the new source is live.
