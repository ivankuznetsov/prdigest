# PRDigest OpenClaw skill

PRDigest owns one published OpenClaw skill. Its canonical local source is
[`skills/prdigest/SKILL.md`](skills/prdigest/SKILL.md); the bundle contains no
Ruby runtime, executable, credentials, or configuration.

The skill invokes only the versioned `prdigest facts` boundary. OpenClaw writes
the prose itself from that document. It does not invoke PRDigest's provider or
Telegram paths, or query GitHub directly.

The Ruby gem and ClawHub skill have independent version histories. The current
Ruby release is `0.3.0`; the
[`@ivankuznetsov/prdigest`](https://clawhub.ai/ivankuznetsov/skills/prdigest)
skill is published separately under **Development**.

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
`openclaw skills install @ivankuznetsov/prdigest`. This message
explicitly authorizes those two installs and only the PATH adjustment needed to
make the installed `prdigest` executable visible to the OpenClaw runtime. Do
not create PRDigest configuration files, store credentials, enable Telegram
delivery, or install a scheduler. First verify Ruby 3.2 or newer is available;
if it is not, stop and report the exact blocker instead of changing system
packages. After installation, run `prdigest version`, confirm that OpenClaw can
discover the installed PRDigest skill, and report the installed paths and
versions without exposing environment variables or tokens.
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
4. Authenticate with `npm exec --yes clawhub@latest -- login`, then run
   `npm exec --yes clawhub@latest -- whoami` and confirm it reports the
   intended owner.
5. Publish exactly the absolute `openclaw/skills/prdigest` directory with
   `npm exec --yes clawhub@latest -- skill publish <absolute-path>` and the
   separately authorized owner, slug, and version. Do not publish the parent
   `openclaw` directory.
6. Wait until
   `npm exec --yes clawhub@latest -- inspect prdigest --versions --limit 10 --json`
   lists the requested skill version. Then run
   `npm exec --yes clawhub@latest -- inspect prdigest --version <skill-version> --file SKILL.md --json`
   and require `owner.handle` to be `ivankuznetsov`, `skill.slug` to be
   `prdigest`, `version.version` to match the requested skill version,
   `version.security.status` to be `clean`, and `file.content` to be
   byte-for-byte identical to the reviewed `SKILL.md`.
7. Install `@ivankuznetsov/prdigest` into a clean temporary workspace and
   confirm OpenClaw discovers the installed skill.
8. Run an authenticated OpenClaw smoke that discovers the skill and produces a
   bounded digest from a safe test repository without exposing facts or
   credentials in retained logs.

Treat authenticated ClawHub inspection as the authority for the latest verified
skill publication. Do not infer the skill version from the Ruby gem version.
