# frozen_string_literal: true

require "cgi"

module Prdigest
  class ProseRenderer
    DISALLOWED_CONTROL_CHARACTERS = /[\u0000-\u0008\u000B-\u001F\u007F-\u009F]/

    def initialize(limit: 4_096)
      @limit = Integer(limit)
      raise ArgumentError, "limit must be positive" unless @limit.positive?
    end

    def render(value)
      text = value.to_s
      if text.match?(/\A[[:space:]]*\z/)
        raise RenderError.new("prose provider output is blank", kind: "prose_render")
      end
      if text.match?(DISALLOWED_CONTROL_CHARACTERS)
        raise RenderError.new(
          "prose provider output contains disallowed control characters",
          kind: "prose_render"
        )
      end

      chunks = text.each_char.each_slice(@limit).map do |characters|
        CGI.escapeHTML(characters.join).freeze
      end
      Renderer::Output.new(chunks.freeze, "rendered")
    rescue RenderError
      raise
    rescue StandardError => e
      raise RenderError.new("prose rendering failed: #{e.class}", kind: "prose_render")
    end
  end
end
