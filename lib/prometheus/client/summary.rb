# encoding: UTF-8

require 'prometheus/client/metric'
require 'prometheus/client/windowed_sample_stream'

module Prometheus
  module Client
    # Summary is an accumulator for samples. It captures Numeric data and
    # provides an efficient quantile calculation mechanism. Sliding time
    # windows are provided by WindowedSampleStream; this ensures that quantile
    # calculations only account for observations added in the last 10 minutes.
    # The Quantile::Estimator implementation doesn't natively support this
    # concept, so a strategy similar to that used in the Go client is used to
    # exclude observations that are no longer relevant.
    class Summary < Metric
      # Value represents the state of a Summary at a given point.
      class Value
        attr_accessor :sum, :total, :quantiles

        def initialize(attrs = {})
          self.sum = attrs[:sum]
          self.total = attrs[:total]
          self.quantiles = attrs[:quantiles]
        end

        def self.build(estimator)
          quantiles = {}
          estimator.invariants.each do |invariant|
            quantiles[invariant.quantile] = estimator.query(invariant.quantile)
          end

          new(
            sum: estimator.sum,
            total: estimator.observations,
            quantiles: quantiles,
          )
        end

        def ==(other)
          other.is_a?(Value) &&
            total     == other.total &&
            sum       == other.sum &&
            quantiles == other.quantiles
        end

        def eql?(other)
          other.class.equal?(self.class) && self == other
        end
      end

      def type
        :summary
      end

      # Records a given value.
      def add(labels, value)
        label_set = label_set_for(labels)
        synchronize { @values[label_set].add(value) }
      end

      # Returns the value for the given label set
      def get(labels = {})
        @validator.valid?(labels)

        synchronize do
          Value.build(@values[labels].head_window)
        end
      end

      # Returns all label sets with their values
      def values
        synchronize do
          @values.each_with_object({}) do |(labels, value), memo|
            memo[labels] = Value.build(value.head_window)
          end
        end
      end

      private

      def default
        WindowedSampleStream.new(add_method: :observe) { Quantile::Estimator.new }
      end
    end
  end
end
