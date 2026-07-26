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
  class RenderError < Error
    attr_reader :kind

    def initialize(message, kind: "render")
      @kind = kind
      super(message)
    end
  end
  class GenerationError < Error
    attr_reader :kind

    def initialize(message, kind: "provider")
      @kind = kind
      super(message)
    end
  end
  class SendError < Error
    attr_reader :kind, :delivery

    def initialize(message, kind: "telegram", delivery: {})
      @kind = kind
      @delivery = delivery.transform_keys(&:to_sym).freeze
      super(message)
    end
  end
end

require_relative "prdigest/version"
require_relative "prdigest/clock"
require_relative "prdigest/config"
require_relative "prdigest/digest"
require_relative "prdigest/github"
require_relative "prdigest/collector"
require_relative "prdigest/facts"
require_relative "prdigest/facts_runner"
require_relative "prdigest/openai_compatible"
require_relative "prdigest/renderer"
require_relative "prdigest/prose_renderer"
require_relative "prdigest/delivery_checkpoint_store"
require_relative "prdigest/telegram"
require_relative "prdigest/result"
require_relative "prdigest/schedule"
require_relative "prdigest/state"
require_relative "prdigest/runner"
require_relative "prdigest/cli"
