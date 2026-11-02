# frozen_string_literal: true

module Archsight
  module Pdf
    # The last PDFs that were made, by fingerprint of what they were made from, and a limit on how many are made at
    # the same time (typst needs a CPU for seconds, a page nobody changed needs none).
    class Cache
      def initialize(entries: 16, parallel: 2)
        @entries = entries
        @store = {}
        @lock = Mutex.new
        @slots = SizedQueue.new(parallel)
        parallel.times { @slots << true }
      end

      # @param key [String] fingerprint
      # @yield makes the PDF when it is not cached
      # @return [String]
      def fetch(key, &)
        cached = @lock.synchronize { @store.delete(key)&.tap { |pdf| @store[key] = pdf } }
        return cached if cached

        pdf = make(&)
        @lock.synchronize do
          @store[key] = pdf
          @store.shift while @store.size > @entries
        end
        pdf
      end

      private

      def make
        @slots.pop
        yield
      ensure
        @slots << true
      end
    end
  end
end
