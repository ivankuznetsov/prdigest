# frozen_string_literal: true

require_relative "prdigest/version"
require_relative "prdigest/cli"
require_relative "prdigest/config"
require_relative "prdigest/runner"

module Prdigest
  class Error < StandardError; end
  class ConfigError < Error; end
end
