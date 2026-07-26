# PRDigest OpenClaw skill

PRDigest owns one ClawHub-ready OpenClaw skill. Its canonical local source is
[`skills/prdigest/SKILL.md`](skills/prdigest/SKILL.md); the bundle contains no
Ruby runtime, executable, credentials, or configuration.

The skill invokes only the versioned `prdigest facts` boundary. OpenClaw writes
the prose itself from that document. It does not invoke deterministic Telegram
delivery, PRDigest's optional provider mode, or GitHub directly.

The coordinated source release target is `0.2.0`. ClawHub publication remains a
separate operator-authorized action after that exact gem is publicly installable.

## Installation boundary

ClawHub publication is not part of normal build or test work. After a separately
authorized publication, the expected install command and slug are:

```sh
clawhub install @ivankuznetsov/prdigest
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

Publishing is a release action. Do not run any publish command—including a
dry-run—without a separate explicit release request and version direction. A
dry-run can still select default version metadata even though it does not
upload the skill.

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

Until those checks pass, describe the source as ClawHub-ready rather than
published.
