# encoding: UTF-8

require 'prometheus/client/summary'
require 'examples/metric_example'
require 'timecop'

describe Prometheus::Client::Summary do
  let(:summary) { Prometheus::Client::Summary.new(:bar, 'bar description') }

  it_behaves_like Prometheus::Client::Metric do
    let(:type) { Hash }
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
        Prometheus::Client::Summary::SlidingWindowEstimator::MAX_AGE
    end

    before do
      Timecop.freeze(start_time)
      summary.add({ foo: 'bar' }, 3)
      summary.add({ foo: 'bar' }, 5.2)
      summary.add({ foo: 'bar' }, 13)
      summary.add({ foo: 'bar' }, 4)
    end

    after do
      Timecop.return
    end

    it 'returns a set of quantile values' do
      expect(summary.get(foo: 'bar')).to eql(0.5 => 4, 0.9 => 5.2, 0.99 => 5.2)
    end

    it 'returns a value which responds to #sum and #total' do
      value = summary.get(foo: 'bar')

      expect(value.sum).to eql(25.2)
      expect(value.total).to eql(4)
    end

    it 'uses nil as default value' do
      expect(summary.get({})).to eql(0.5 => nil, 0.9 => nil, 0.99 => nil)
    end

    describe 'expiration' do
      it 'should have the same values just before expiration' do
        expected = { 0.5 => 4, 0.9 => 5.2, 0.99 => 5.2 }
        Timecop.freeze(expiry_time - 5) do
          expect(summary.get(foo: 'bar')).to eql(expected)
        end
      end

      it 'should not have any values just after expiration' do
        expected = { 0.5 => nil, 0.9 => nil, 0.99 => nil }
        Timecop.freeze(expiry_time + 5) do
          expect(summary.get(foo: 'bar')).to eql(expected)
        end
      end
    end
  end

  describe '#values' do
    it 'returns a hash of all recorded summaries' do
      summary.add({ status: 'bar' }, 3)
      summary.add({ status: 'foo' }, 5)

      expect(summary.values).to eql(
        { status: 'bar' } => { 0.5 => 3, 0.9 => 3, 0.99 => 3 },
        { status: 'foo' } => { 0.5 => 5, 0.9 => 5, 0.99 => 5 },
      )
    end
  end
end
