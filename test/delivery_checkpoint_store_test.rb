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
