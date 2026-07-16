# frozen_string_literal: true

module Prdigest
  class Error < StandardError; end
  class ConfigError < Error; end
  class StateError < Error; end
end

require_relative "prdigest/version"
require_relative "prdigest/clock"
require_relative "prdigest/config"
require_relative "prdigest/schedule"
require_relative "prdigest/state"
require_relative "prdigest/runner"
require_relative "prdigest/cli"
