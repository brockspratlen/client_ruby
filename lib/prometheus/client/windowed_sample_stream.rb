# encoding: UTF-8

require 'quantile'

module Prometheus
  module Client
    # WindowedSampleStream mirrors the approach of the "AgeBuckets" used in the
    # go client's Summary implementation. As samples are observed, they are
    # applied to each of the current WINDOW_COUNT windows. The oldest window is
    # expired every WINDOW_INTERVAL seconds, effectively causing samples
    # observed (MAX_AGE - WINDOW_INTERVAL) seconds ago or before to be discarded.
    class WindowedSampleStream
      attr_accessor :windows, :head_window_index, :head_window_expires_at,
        :observer_builder, :observer_add_method
      MAX_AGE = 10 * 60
      WINDOW_COUNT = 5
      WINDOW_INTERVAL = MAX_AGE.to_f / WINDOW_COUNT

      def initialize(opts = {}, &observer_builder)
        unless self.observer_builder = observer_builder
          raise "missing observer_builder block"
        end
        self.observer_add_method = opts[:add_method] || :add
        self.windows = Array.new(WINDOW_COUNT) { build_observer }
        self.head_window_index = 0
        self.head_window_expires_at = Time.now + WINDOW_INTERVAL
      end

      def build_observer
        observer_builder.call
      end

      def add(value)
        refresh_windows!
        windows.each do |s|
          s.send(observer_add_method, value)
        end
        value
      end

      def head_window
        refresh_windows!
        windows[head_window_index]
      end

      private

      def next_window_expiration(at_time = Time.now)
        delta = (head_window_expires_at - at_time) % WINDOW_INTERVAL
        at_time + delta
      end

      def expired_window_count(at_time = Time.now)
        elapsed_time = (at_time - head_window_expires_at)
        elapsed_intervals = elapsed_time / WINDOW_INTERVAL
        [WINDOW_COUNT, elapsed_intervals.ceil].min
      end

      def refresh_windows!
        now = Time.now
        return unless now > head_window_expires_at
        expired_window_count(now).times do
          windows[head_window_index] = build_observer
          self.head_window_index = (head_window_index + 1) % WINDOW_COUNT
        end
        self.head_window_expires_at = next_window_expiration(now)
      end
    end
  end
end
