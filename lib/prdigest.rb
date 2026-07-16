# frozen_string_literal: true

module Prdigest
  class Error < StandardError; end
  class ConfigError < Error; end
  class StateError < Error; end
  class FetchError < Error
    attr_reader :kind

    def initialize(message, kind: "github")
      @kind = kind
      super(message)
    end
  end
end

require_relative "prdigest/version"
require_relative "prdigest/clock"
require_relative "prdigest/config"
require_relative "prdigest/digest"
require_relative "prdigest/github"
require_relative "prdigest/schedule"
require_relative "prdigest/state"
require_relative "prdigest/runner"
require_relative "prdigest/cli"
