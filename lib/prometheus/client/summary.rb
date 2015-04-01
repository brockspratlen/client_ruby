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

        def initialize(streaming_estimator)
          estimator = streaming_estimator.current_stream.estimator
          @sum, @total = estimator.sum, estimator.observations

          estimator.invariants.each do |invariant|
            self[invariant.quantile] = estimator.query(invariant.quantile)
          end
        end
      end

      class StreamingEstimator
        attr_accessor :streams, :head_stream_index
        MAX_AGE = 10 * 60
        STREAM_COUNT = 5
        STREAM_WIDTH = MAX_AGE.to_f / STREAM_COUNT

        def initialize
          self.streams = Array.new(STREAM_COUNT) { Stream.new }
          self.head_stream_index = 0
        end

        def observe(value)
          refresh_streams!
          streams.each do |s|
            s.estimator.observe(value)
          end
          value
        end

        def current_stream
          refresh_streams!
        end

        def refresh_streams!
          while (head_stream = streams[head_stream_index]).age > MAX_AGE
            head_stream.reset!
            self.head_stream_index = (head_stream_index + 1) % STREAM_COUNT
          end
          head_stream
        end

        class Stream
          attr_reader :estimator, :created_at
          def initialize
            reset!
          end

          def age
            Time.now - created_at
          end

          def reset!
            @created_at = Time.now
            @estimator = Quantile::Estimator.new
          end
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
        StreamingEstimator.new
      end
    end
  end
end
