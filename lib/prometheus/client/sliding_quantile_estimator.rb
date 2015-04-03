# encoding: UTF-8

require 'quantile'

module Prometheus
  module Client
    # SlidingQuantileEstimator ensures that quantile calculations only account
    # for observations added in the last 10 minutes. The Quantile::Estimator
    # implementation doesn't natively support this concept, so a strategy
    # similar to that used in the Go client is used to exclude observations
    # that are no longer relevant.
    class SlidingQuantileEstimator
      attr_accessor :windows, :head_window_index, :head_window_expires_at,
        :quantile_estimator_builder
      MAX_AGE = 10 * 60
      WINDOW_COUNT = 5
      WINDOW_INTERVAL = MAX_AGE.to_f / WINDOW_COUNT

      def initialize(&qe_builder)
        qe_builder ||= Proc.new { Quantile::Estimator.new }
        self.quantile_estimator_builder = qe_builder
        self.windows = Array.new(WINDOW_COUNT) { build_quantile_estimator }
        self.head_window_index = 0
        self.head_window_expires_at = Time.now + WINDOW_INTERVAL
      end

      def build_quantile_estimator
        quantile_estimator_builder.call
      end

      def observe(value)
        refresh_windows!
        windows.each do |s|
          s.observe(value)
        end
        value
      end

      def head_window
        # require 'pry'; binding.pry if $pry
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
          windows[head_window_index] = build_quantile_estimator
          self.head_window_index = (head_window_index + 1) % WINDOW_COUNT
        end
        self.head_window_expires_at = next_window_expiration(now)
      end
    end
  end
end
