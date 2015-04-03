# encoding: UTF-8

require 'prometheus/client/sliding_quantile_estimator'
require 'timecop'

class MockQuantileEstimator
  attr_accessor :samples

  def initialize
    self.samples = []
  end

  def observe(value)
    samples << value
  end
end

describe Prometheus::Client::SlidingQuantileEstimator do
    subject { Prometheus::Client::SlidingQuantileEstimator.new { MockQuantileEstimator.new } }

    let(:start_time) { Time.now }

    let(:expiry_time) do
      start_time +
        Prometheus::Client::SlidingQuantileEstimator::MAX_AGE
    end

    let(:window_interval) do
      Prometheus::Client::SlidingQuantileEstimator::WINDOW_INTERVAL
    end

    let(:window_count) do
      Prometheus::Client::SlidingQuantileEstimator::WINDOW_COUNT
    end

    def ordered_windows
      subject.windows.rotate(subject.head_window_index)
    end

    describe "#windows" do
      before do
        Timecop.freeze(start_time)
        @samples = []
        [3, 5.2, 13, 4].each do |o|
          @samples << o
          subject.observe(o)
        end
      end

      after do
        Timecop.return
      end

      it "every window should have all samples" do
        expect(subject.windows.any?{|w| w.samples != @samples }).to eq(false)
      end

      context "just before first window expires" do
        before { Timecop.freeze(start_time + window_interval - 0.1) }
        it "all windows should have all samples" do
          expect(subject.windows.any?{|w| w.samples != @samples }).to eq(false)
        end
      end

      context "just after first window expires" do
        before { Timecop.freeze(start_time + window_interval + 0.1) }
        it "all but the newest window should have all samples" do
          subject.head_value # force refresh
          old_windows = ordered_windows
          new_window = old_windows.pop

          expect(old_windows.any?{|w| w.samples != @samples }).to eq(false)
          expect(new_window.samples.count).to eq(0)
        end
      end
    end
end
