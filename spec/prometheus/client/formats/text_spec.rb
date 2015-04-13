# encoding: UTF-8

require 'prometheus/client/formats/text'
require 'prometheus/client/summary'

describe Prometheus::Client::Formats::Text do
  let(:summary_value) do
    Prometheus::Client::Summary::Value.new(
      sum: 1243.21,
      total: 93,
      quantiles: { 0.5  => 4.2, 0.9  => 8.32, 0.99 => 15.3 },
    )
  end

  let(:empty_summary_value) do
    Prometheus::Client::Summary::Value.new(
      sum: 0,
      total: 0,
      quantiles: { 0.5  => nil, 0.9  => nil, 0.99 => nil },
    )
  end

  let(:registry) do
    double(metrics: [
      double(
        name: :foo,
        docstring: 'foo description',
        base_labels: { umlauts: 'Björn', utf: '佖佥' },
        type: :counter,
        values: {
          { code: 'red' }   => 42,
          { code: 'green' } => 3.14E42,
          { code: 'blue' }  => -1.23e-45,
        },
      ),
      double(
        name: :bar,
        docstring: "bar description\nwith newline",
        base_labels: { status: 'success' },
        type: :gauge,
        values: { { code: 'pink' } => 15 },
      ),
      double(
        name: :baz,
        docstring: 'baz "description" \\escaping',
        base_labels: {},
        type: :counter,
        values: { { text: "with \"quotes\", \\escape \n and newline" } => 15 },
      ),
      double(
        name: :qux,
        docstring: 'qux description',
        base_labels: { for: 'sake' },
        type: :summary,
        values: { { code: '1' } => summary_value },
      ),
      double(
        name: :qux_empty,
        docstring: 'qux_empty description',
        base_labels: { for: 'sake' },
        type: :summary,
        values: { { code: 'empty' } => empty_summary_value },
      ),
    ])
  end

  describe '.marshal' do
    it 'returns a Text format version 0.0.4 compatible representation' do
      expect(subject.marshal(registry)).to eql <<-'TEXT'
# TYPE foo counter
# HELP foo foo description
foo{umlauts="Björn",utf="佖佥",code="red"} 42
foo{umlauts="Björn",utf="佖佥",code="green"} 3.14e+42
foo{umlauts="Björn",utf="佖佥",code="blue"} -1.23e-45
# TYPE bar gauge
# HELP bar bar description\nwith newline
bar{status="success",code="pink"} 15
# TYPE baz counter
# HELP baz baz "description" \\escaping
baz{text="with \"quotes\", \\escape \n and newline"} 15
# TYPE qux summary
# HELP qux qux description
qux{for="sake",code="1",quantile="0.5"} 4.2
qux{for="sake",code="1",quantile="0.9"} 8.32
qux{for="sake",code="1",quantile="0.99"} 15.3
qux_sum{for="sake",code="1"} 1243.21
qux_total{for="sake",code="1"} 93
# TYPE qux_empty summary
# HELP qux_empty qux_empty description
qux_empty{for="sake",code="empty",quantile="0.5"} NaN
qux_empty{for="sake",code="empty",quantile="0.9"} NaN
qux_empty{for="sake",code="empty",quantile="0.99"} NaN
qux_empty_sum{for="sake",code="empty"} 0
qux_empty_total{for="sake",code="empty"} 0
      TEXT
    end
  end
end
