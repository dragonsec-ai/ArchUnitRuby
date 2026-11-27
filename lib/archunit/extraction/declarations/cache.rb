# frozen_string_literal: true

module ArchUnit
  module Extraction
    module Declarations
      # Shares completed immutable inventories only; failed reads never populate the cache.
      module Cache
        MUTEX = Mutex.new
        private_constant :MUTEX

        def self.fetch(key, refresh:)
          MUTEX.synchronize do
            @entries ||= {}
            @entries.delete(key) if refresh
            if @entries.key?(key)
              [@entries.fetch(key), true]
            else
              [@entries[key] = yield, false]
            end
          end
        end

        def self.clear
          MUTEX.synchronize { @entries&.clear }
        end
      end
    end
  end
end
