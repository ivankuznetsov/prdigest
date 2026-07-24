# frozen_string_literal: true

require "cgi"

module Prdigest
  class Renderer
    Output = Data.define(:chunks, :outcome)
    SUPPORTED_TAG = %r{</?(?:b|a)(?:\s+href="[^"]*")?>}.freeze

    def self.parsed_length(html)
      CGI.unescapeHTML(html.gsub(SUPPORTED_TAG, "")).length
    end

    def initialize(send_empty:, empty_message:, limit: 4_096)
      @send_empty = send_empty
      @empty_message = empty_message.to_s
      @limit = Integer(limit)
    end

    def render(digest)
      return render_empty(digest) if digest.total_prs.zero?

      pack(digest)
    rescue RenderError
      raise
    rescue StandardError => e
      raise RenderError, "digest rendering failed: #{e.class}"
    end

    private

    def render_empty(digest)
      return Output.new([].freeze, "suppressed_empty") unless @send_empty

      text = escape(@empty_message.gsub("{date}", digest.date.iso8601))
      raise RenderError, "configured empty message exceeds Telegram limit" unless fits_text?(text)
      Output.new([text.freeze].freeze, "rendered")
    end

    def pack(digest)
      chunks = []
      heading = "<b>Merged PR digest — #{digest.date.iso8601}</b>"
      continuation = "<b>Merged PR digest — #{digest.date.iso8601} (cont.)</b>"
      current = [heading]

      digest.repositories.each do |section|
        next if section.pull_requests.empty?
        current = add_section(chunks, current, continuation, section)
      end

      footer = render_footer(digest)
      unless fits_parts?(current + [footer])
        flush!(chunks, current)
        current = [continuation, footer]
        raise RenderError, "digest footer exceeds Telegram limit" unless fits_parts?(current)
      else
        current << footer
      end
      flush!(chunks, current)
      Output.new(chunks.map(&:freeze).freeze, "rendered")
    end

    def add_section(chunks, current, continuation, section)
      header = "<b>#{escape(section.name)}</b>"
      entries = section.pull_requests.map { |pull| render_pull(pull) }
      whole = ([header] + entries).join("\n")
      if fits_parts?(current + [whole])
        current << whole
        return current
      end

      if current.length > 1
        flush!(chunks, current)
        current = [continuation]
        if fits_parts?(current + [whole])
          current << whole
          return current
        end
      end

      section_part = header
      entries.each do |entry|
        proposed = "#{section_part}\n#{entry}"
        if fits_parts?(current + [proposed])
          section_part = proposed
          next
        end

        if section_part == header
          raise RenderError, "pull request entry exceeds Telegram limit"
        end
        current << section_part
        flush!(chunks, current)
        current = [continuation]
        section_part = "<b>#{escape(section.name)} (cont.)</b>\n#{entry}"
        raise RenderError, "pull request entry exceeds Telegram limit" unless fits_parts?(current + [section_part])
      end
      current << section_part
      current
    end

    def render_pull(pull)
      number_and_title = "##{pull.number} #{pull.title}"
      "• <a href=\"#{escape(pull.url)}\">#{escape(number_and_title)}</a> — @#{escape(pull.author)}"
    end

    def render_footer(digest)
      label = digest.total_prs == 1 ? "PR" : "PRs"
      footer = "<b>Total:</b> #{digest.total_prs} #{label}"
      if digest.line_stats
        footer += " · +#{digest.total_additions}/−#{digest.total_deletions} · #{digest.total_commits} commits"
      end
      footer
    end

    def flush!(chunks, parts)
      text = parts.join("\n\n")
      raise RenderError, "rendered chunk exceeds Telegram limit" unless fits_text?(text)
      chunks << text
    end

    def fits_parts?(parts)
      fits_text?(parts.join("\n\n"))
    end

    def fits_text?(text)
      self.class.parsed_length(text) <= @limit
    end

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
