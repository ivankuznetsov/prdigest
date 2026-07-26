# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class DeliveryCheckpointStoreTest < Minitest::Test
  DATE = Date.new(2026, 7, 23)

  def test_persists_stable_chunks_and_resumes_at_next_unsent_chunk
    with_store do |store, root|
      store.with_checkpoint(
        date: DATE, chat_id: -1001, scope: %w[acme/one acme/two], chunks: %w[one two three]
      ) do |delivery|
        assert_equal %w[one two three], delivery.chunks
        assert_equal 0, delivery.next_chunk
        delivery.begin_attempt(0)
        delivery.accept(0)
      end

      store.with_checkpoint(
        date: DATE, chat_id: -1001, scope: %w[acme/one acme/two], chunks: %w[regenerated content]
      ) do |delivery|
        assert_equal %w[one two three], delivery.chunks
        assert_equal 1, delivery.next_chunk
      end

      assert_equal 0o700, File.stat(root).mode & 0o777
      assert_equal 0o600, File.stat(File.join(root, "#{DATE}.json")).mode & 0o777
    end
  end

  def test_completed_checkpoint_makes_delivery_a_noop
    with_store do |store, _root|
      store.with_checkpoint(date: DATE, chat_id: 1, scope: ["acme/one"], chunks: %w[one two]) do |delivery|
        2.times do |index|
          delivery.begin_attempt(index)
          delivery.accept(index)
        end
        assert delivery.completed?
      end

      store.with_checkpoint(date: DATE, chat_id: 1, scope: ["acme/one"], chunks: %w[new body]) do |delivery|
        assert delivery.completed?
        assert_equal 2, delivery.next_chunk
        assert_equal %w[one two], delivery.chunks
      end
    end
  end

  def test_lazy_factory_is_called_once_and_never_called_for_an_existing_checkpoint
    with_store do |store, _root|
      calls = 0
      store.with_checkpoint(
        date: DATE,
        chat_id: 1,
        scope: ["acme/one"],
        chunk_factory: -> {
          calls += 1
          %w[generated once]
        }
      ) do |delivery|
        assert_equal %w[generated once], delivery.chunks
      end

      store.with_checkpoint(
        date: DATE,
        chat_id: 1,
        scope: ["acme/one"],
        chunk_factory: -> { flunk "existing checkpoint must bypass generation" }
      ) do |delivery|
        assert_equal %w[generated once], delivery.chunks
      end

      assert_equal 1, calls
    end
  end

  def test_lazy_factory_output_is_persisted_before_delivery_begins
    with_store do |store, root|
      store.with_checkpoint(
        date: DATE,
        chat_id: 1,
        scope: ["acme/one"],
        chunk_factory: -> { ["durable prose"] }
      ) do |delivery|
        checkpoint = JSON.parse(File.read(File.join(root, "#{DATE}.json")))
        assert_equal ["durable prose"], checkpoint.fetch("chunks")
        assert_equal "pending", checkpoint.fetch("status")
        assert_equal ["durable prose"], delivery.chunks
      end
    end
  end

  def test_lazy_factory_preserves_domain_error_types_and_creates_no_checkpoint
    with_store do |store, root|
      failures = [
        Prdigest::ConfigError.new("configuration unavailable"),
        Prdigest::FetchError.new("GitHub unavailable"),
        Prdigest::GenerationError.new("provider unavailable"),
        Prdigest::RenderError.new("render unavailable")
      ]

      failures.each do |failure|
        error = assert_raises(failure.class) do
          store.with_checkpoint(
            date: DATE,
            chat_id: 1,
            scope: ["acme/one"],
            chunk_factory: -> { raise failure }
          ) { flunk "delivery must not begin" }
        end

        assert_same failure, error
        refute File.exist?(File.join(root, "#{DATE}.json"))
      end
    end
  end

  def test_new_checkpoint_requires_exactly_one_payload_source
    with_store do |store, _root|
      error = assert_raises(Prdigest::StateError) do
        store.with_checkpoint(date: DATE, chat_id: 1, scope: ["acme/one"]) { flunk }
      end
      assert_match(/exactly one payload source/, error.message)
    end

    with_store do |store, _root|
      error = assert_raises(Prdigest::StateError) do
        store.with_checkpoint(
          date: DATE,
          chat_id: 1,
          scope: ["acme/one"],
          chunks: ["eager"],
          chunk_factory: -> { ["lazy"] }
        ) { flunk }
      end
      assert_match(/exactly one payload source/, error.message)
    end
  end

  def test_existing_checkpoint_ignores_all_payload_sources
    with_store do |store, _root|
      store.with_checkpoint(
        date: DATE,
        chat_id: 1,
        scope: ["acme/one"],
        chunks: ["stored"]
      ) { }

      store.with_checkpoint(
        date: DATE,
        chat_id: 1,
        scope: ["acme/one"],
        chunks: ["regenerated"],
        chunk_factory: -> { flunk "existing checkpoint must not inspect payload sources" }
      ) do |delivery|
        assert_equal ["stored"], delivery.chunks
      end
    end
  end

  def test_in_flight_attempt_is_parked_as_ambiguous
    with_store do |store, _root|
      store.with_checkpoint(date: DATE, chat_id: 1, scope: ["acme/one"], chunks: ["one"]) do |delivery|
        delivery.begin_attempt(0)
      end

      error = assert_raises(Prdigest::SendError) do
        store.with_checkpoint(date: DATE, chat_id: 1, scope: ["acme/one"], chunks: ["one"]) { flunk }
      end
      assert_equal "telegram_ambiguous", error.kind
      assert_equal 0, error.delivery.fetch(:failed_chunk)
    end
  end

  def test_permanent_rejection_stays_blocked_without_reopening_delivery
    with_store do |store, _root|
      store.with_checkpoint(date: DATE, chat_id: 1, scope: ["acme/one"], chunks: ["one"]) do |delivery|
        delivery.begin_attempt(0)
        delivery.reject(0, kind: "telegram_permanent", message: "HTTP 400", permanent: true)
      end

      error = assert_raises(Prdigest::SendError) do
        store.with_checkpoint(date: DATE, chat_id: 1, scope: ["acme/one"], chunks: ["one"]) { flunk }
      end
      assert_equal "telegram_permanent", error.kind
      assert_equal 0, error.delivery.fetch(:failed_chunk)
    end
  end

  def test_scope_change_for_same_date_fails_closed
    with_store do |store, _root|
      store.with_checkpoint(date: DATE, chat_id: 1, scope: ["acme/one"], chunks: ["one"]) { }

      error = assert_raises(Prdigest::SendError) do
        store.with_checkpoint(date: DATE, chat_id: 1, scope: ["acme/two"], chunks: ["two"]) { flunk }
      end
      assert_equal "delivery_checkpoint_permanent", error.kind
    end
  end

  private

  def with_store
    Dir.mktmpdir do |root|
      yield Prdigest::DeliveryCheckpointStore.new(root: root), root
    end
  end
end
