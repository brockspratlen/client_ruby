# encoding: UTF-8

require 'prometheus/client/summary'
require 'examples/metric_example'
require 'timecop'

describe Prometheus::Client::Summary do
  let(:summary) { Prometheus::Client::Summary.new(:bar, 'bar description') }

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { Prometheus::Client::Summary::Value }
  end

  def build_value(attrs = {})
    Prometheus::Client::Summary::Value.new(attrs)
  end

  describe '#add' do
    it 'records the given value' do
      expect do
        summary.add({}, 5)
      end.to change { summary.get }
    end
  end

  describe '#get' do
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

    let(:empty_value) do
      build_value(
        sum: 0,
        total: 0,
        quantiles: { 0.5 => nil, 0.9 => nil, 0.99 => nil },
      )
    end

    before do
      Timecop.freeze(start_time)
      summary.add({ foo: 'bar' }, 3)
      summary.add({ foo: 'bar' }, 5.2)
      summary.add({ foo: 'bar' }, 13)
      summary.add({ foo: 'bar' }, 4)
      @expected_value = build_value(
        sum: 25.2,
        total: 4,
        quantiles: { 0.5 => 4, 0.9 => 5.2, 0.99 => 5.2 },
      )
    end

    after do
      Timecop.return
    end

    it 'returns a value with the correct sum, total, and quantiles' do
      expect(summary.get(foo: 'bar')).to eql(@expected_value)
    end

    it 'uses nil as default value' do
      expect(summary.get({})).to eql(empty_value)
    end

    describe 'expiration' do
      it 'should have the same values just before expiration' do
        Timecop.freeze(expiry_time - 5) do
          expect(summary.get(foo: 'bar')).to eql(@expected_value)
        end
      end

      it 'should not have any values just after expiration' do
        Timecop.freeze(expiry_time + 5) do
          expect(summary.get(foo: 'bar')).to eql(empty_value)
        end
      end

      describe 'windows' do
        it 'should expire observations in windows' do
          Timecop.freeze(start_time + window_interval - 0.1)
          summary.add({ foo: 'bar' }, 12)
          summary.add({ foo: 'bar' }, 6.7)
          expected = build_value(
            sum: 43.900000000000006,
            total: 6,
            quantiles: { 0.5 => 5.2, 0.9 => 6.7, 0.99 => 6.7 },
          )
          expect(summary.get(foo: 'bar')).to eql(expected)

          Timecop.freeze(start_time + window_interval + 0.1)
          expect(summary.get(foo: 'bar')).to eql(expected)

          summary.add({ foo: 'bar' }, 11)
          summary.add({ foo: 'bar' }, 20)
          summary.add({ foo: 'bar' }, 18)
          expected = build_value(
            sum: 92.9,
            total: 9,
            quantiles: { 0.5 => 5.2, 0.9 => 12, 0.99 => 12 },
          )
          expect(summary.get(foo: 'bar')).to eql(expected)
          expect(summary.get(foo: 'bar')).to eql(expected)

          # puts "TROUBLE SPOT"
          # Timecop.freeze(start_time + window_count * window_interval - 5)
          # expect(summary.get(foo: 'bar')).to eql(expected)
        end
      end
    end
  end

  describe '#values' do
    it 'returns a hash of all recorded summaries' do
      summary.add({ status: 'bar' }, 3)
      summary.add({ status: 'foo' }, 5)

      bar_expected = build_value(
        sum: 3,
        total: 1,
        quantiles: { 0.5 => 3, 0.9 => 3, 0.99 => 3 },
      )

      foo_expected = build_value(
        sum: 5,
        total: 1,
        quantiles: { 0.5 => 5, 0.9 => 5, 0.99 => 5 },
      )

      expect(summary.values).to eql(
        { status: 'bar' } => bar_expected,
        { status: 'foo' } => foo_expected,
      )
    end
  end
end
