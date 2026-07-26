# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class ReleaseWorkflowTest < Minitest::Test
  WORKFLOW = File.expand_path("../.github/workflows/release.yml", __dir__)

  def setup
    @source = File.read(WORKFLOW)
  end

  def test_release_workflow_is_valid_yaml
    parsed = YAML.safe_load(@source, aliases: false)

    assert_instance_of Hash, parsed
    assert parsed.key?("jobs")
  end

  def test_release_workflow_fails_closed_before_requesting_credentials
    assert_includes @source, '[[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]'
    assert_includes @source, 'test "v${gem_version}" = "$RELEASE_TAG"'
    assert_includes @source, 'git describe --tags --exact-match HEAD'
    assert_includes @source, "bundle exec rake test"
    assert_includes @source, "test/smoke/gem_install.sh"

    credentials = @source.index("Configure short-lived RubyGems credentials")
    push = @source.index('gem push "pkg/prdigest-${GEM_VERSION}.gem"')

    assert_operator credentials, :>, @source.index("test/smoke/gem_install.sh")
    assert_operator push, :>, credentials
  end

  def test_release_workflow_uses_oidc_without_repository_secrets
    assert_includes @source, "environment: release"
    assert_includes @source, "id-token: write"
    assert_includes @source,
                    "rubygems/configure-rubygems-credentials@dc5a8d8553e6ee01fc26761a49e99e733d17954a"
    refute_includes @source, "secrets."
  end

  def test_release_workflow_can_backfill_an_existing_tag
    assert_includes @source, "workflow_dispatch:"
    assert_includes @source, "ref: ${{ env.RELEASE_TAG }}"
    assert_includes @source, 'RELEASE_TAG: ${{ inputs.tag || github.ref_name }}'
  end
end
