# frozen_string_literal: true

require_relative "test_helper"

class PackagingTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_release_version_and_deterministic_gem_manifest
    assert_equal "0.1.0", Prdigest::VERSION
    spec = Gem::Specification.load(File.join(ROOT, "prdigest.gemspec"))
    %w[exe/prdigest README.md LICENSE CHANGELOG.md SECURITY.md lib/prdigest/runner.rb].each do |path|
      assert_includes spec.files, path
    end
    refute spec.files.any? { |path| path.start_with?("test/", "bin/") }
  end

  def test_container_is_non_root_and_includes_timezone_data
    dockerfile = File.read(File.join(ROOT, "Dockerfile"))
    assert_match(/apk add .*tzdata/, dockerfile)
    assert_match(/^USER prdigest$/, dockerfile)
  end

  def test_systemd_owns_state_and_bounds_runtime
    service = File.read(File.join(ROOT, "scripts/systemd/prdigest.service"))
    assert_match(/^StateDirectory=prdigest$/, service)
    assert_match(/^StateDirectoryMode=0700$/, service)
    assert_match(/^UMask=0077$/, service)
    assert_match(/^TimeoutStartSec=1h$/, service)
  end

  def test_webmock_blocks_unstubbed_network
    assert_raises(WebMock::NetConnectNotAllowedError) do
      Net::HTTP.get(URI("https://example.invalid/prdigest-offline-proof"))
    end
  end
end
