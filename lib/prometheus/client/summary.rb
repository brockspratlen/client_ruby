# encoding: UTF-8

require 'quantile'
require 'prometheus/client/metric'

module Prometheus
  module Client
    # Summary is an accumulator for samples. It captures Numeric data and
    # provides an efficient quantile calculation mechanism.
    class Summary < Metric
      # Value represents the state of a Summary at a given point.
      class Value < Hash
        attr_accessor :sum, :total

        def initialize(swe)
          estimator = swe.current
          @sum, @total = estimator.sum, estimator.observations

          estimator.invariants.each do |invariant|
            self[invariant.quantile] = estimator.query(invariant.quantile)
          end
        end
      end

      # SlidingWindowEstimator ensures that quantile calculations only account
      # for observations added in the last 10 minutes. The Quantile::Estimator
      # implementation doesn't natively support this concept, so a strategy
      # similar to that used in the Go client is used to exclude observations
      # that are no longer relevant.
      class SlidingWindowEstimator
        attr_accessor :windows, :head_window_index, :head_window_expires_at
        MAX_AGE = 10 * 60
        WINDOW_COUNT = 5
        WINDOW_INTERVAL = MAX_AGE.to_f / WINDOW_COUNT

        def initialize
          self.windows = Array.new(WINDOW_COUNT) { default_value }
          self.head_window_index = 0
          self.head_window_expires_at = Time.now + WINDOW_INTERVAL
        end

        def default_value
          Quantile::Estimator.new
        end

        def observe(value)
          refresh_windows!
          windows.each do |s|
            s.observe(value)
          end
          value
        end

        def current
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
            windows[head_window_index] = default_value
            self.head_window_index = (head_window_index + 1) % WINDOW_COUNT
          end
          self.head_window_expires_at = next_window_expiration(now)
        end
      end

      def type
        :summary
      end

      # Records a given value.
      def add(labels, value)
        label_set = label_set_for(labels)
        synchronize { @values[label_set].observe(value) }
      end

      # Returns the value for the given label set
      def get(labels = {})
        @validator.valid?(labels)

        synchronize do
          Value.new(@values[labels])
        end
      end

      # Returns all label sets with their values
      def values
        synchronize do
          @values.each_with_object({}) do |(labels, value), memo|
            memo[labels] = Value.new(value)
          end
        end
      end

      private

      def default
        SlidingWindowEstimator.new
      end
    end
  end
end
