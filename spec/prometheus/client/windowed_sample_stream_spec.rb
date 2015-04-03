# encoding: UTF-8

require 'prometheus/client/windowed_sample_stream'
require 'timecop'

# SimpleObserver is used as a dead-simple observer to provide to
# WindowedSampleStream that we can then make assertions against.
class SimpleObserver
  attr_accessor :samples

  def initialize
    self.samples = []
  end

  def observe(value)
    samples << value
  end
end

describe Prometheus::Client::WindowedSampleStream do
  subject do
    Prometheus::Client::WindowedSampleStream.new(add_method: :observe) do
      SimpleObserver.new
    end
  end

  let(:start_time) { Time.now }

  let(:expiry_time) do
    start_time +
      Prometheus::Client::WindowedSampleStream::MAX_AGE
  end

  let(:window_interval) do
    Prometheus::Client::WindowedSampleStream::WINDOW_INTERVAL
  end

  let(:window_count) do
    Prometheus::Client::WindowedSampleStream::WINDOW_COUNT
  end

  def ordered_windows
    subject.windows.rotate(subject.head_window_index)
  end

  describe '#windows' do
    before do
      Timecop.freeze(start_time)
      @samples = []
      [1, 2.0, 3, 4.2].each do |o|
        @samples << o
        subject.add(o)
      end
    end

    after do
      Timecop.return
    end

    it 'every window should have all samples' do
      expect(subject.windows.any? { |w| w.samples != @samples }).to eq(false)
    end

    context 'just before first window expires' do
      before { Timecop.freeze(start_time + window_interval - 0.1) }
      it 'all windows should have all samples' do
        expect(subject.windows.any? { |w| w.samples != @samples }).to eq(false)
        expect(subject.head_window.samples).to eq(@samples)
      end
    end

    context 'just after first window expires' do
      before { Timecop.freeze(start_time + window_interval + 0.1) }
      it 'all but the newest window should have all samples' do
        head_window = subject.head_window # force refresh
        old_windows = ordered_windows
        new_window = old_windows.pop

        expect(head_window.samples).to eq(@samples)
        expect(old_windows.any? { |w| w.samples != @samples }).to eq(false)
        expect(new_window.samples.count).to eq(0)
      end
    end

    it 'expires with interspersed samples'do
      s1 = @samples

      Timecop.freeze(start_time + window_interval + 0.1)
      s2 = [5, 6, 7.1, 8].each { |s| subject.add(s) }
      expect(subject.head_window.samples).to eq(s1 + s2)

      Timecop.freeze(start_time + 2 * window_interval + 0.1)
      s3 = [9, 10, 11, 12].each { |s| subject.add(s) }
      expect(subject.head_window.samples).to eq(s1 + s2 + s3)

      Timecop.freeze(start_time + 3 * window_interval + 0.1)
      s4 = [13, 14, 15].each { |s| subject.add(s) }
      expect(subject.head_window.samples).to eq(s1 + s2 + s3 + s4)

      Timecop.freeze(start_time + 4 * window_interval + 0.1)
      s5 = [16, 17, 18.1].each { |s| subject.add(s) }
      expect(subject.head_window.samples).to eq(s1 + s2 + s3 + s4 + s5)

      Timecop.freeze(start_time + 5 * window_interval + 0.1)
      # first batch of samples (s1 aka @samples) should have expired now
      expect(subject.head_window.samples).to eq(s2 + s3 + s4 + s5)
      s6 = [19, 20, 21, 22].each { |s| subject.add(s) }
      expect(subject.head_window.samples).to eq(s2 + s3 + s4 + s5 + s6)

      Timecop.freeze(start_time + 6 * window_interval + 0.1)
      # s2 should have expired now
      expect(subject.head_window.samples).to eq(s3 + s4 + s5 + s6)
      s7 = [23, 24].each { |s| subject.add(s) }
      expect(subject.head_window.samples).to eq(s3 + s4 + s5 + s6 + s7)

      Timecop.freeze(start_time + 7 * window_interval + 0.1)
      # s3 should have expired now
      expect(subject.head_window.samples).to eq(s4 + s5 + s6 + s7)
      s8 = [25, 26].each { |s| subject.add(s) }
      expect(subject.head_window.samples).to eq(s4 + s5 + s6 + s7 + s8)

      Timecop.freeze(start_time + 8 * window_interval + 0.1)
      # s4 should have expired now
      expect(subject.head_window.samples).to eq(s5 + s6 + s7 + s8)
      s9 = [27, 28].each { |s| subject.add(s) }
      expect(subject.head_window.samples).to eq(s5 + s6 + s7 + s8 + s9)

      Timecop.freeze(start_time + 9 * window_interval + 0.1)
      # s5 should have expired now
      expect(subject.head_window.samples).to eq(s6 + s7 + s8 + s9)
      s10 = [29, 30.5, 31].each { |s| subject.add(s) }
      expect(subject.head_window.samples).to eq(s6 + s7 + s8 + s9 + s10)

      Timecop.freeze(start_time + 10 * window_interval + 0.1)
      # s6 should have expired now
      expect(subject.head_window.samples).to eq(s7 + s8 + s9 + s10)
      s11 = [32, 33.5, 34, 35, 36].each { |s| subject.add(s) }
      expect(subject.head_window.samples).to eq(s7 + s8 + s9 + s10 + s11)
    end
  end
end
