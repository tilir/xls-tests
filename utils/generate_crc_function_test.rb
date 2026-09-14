#!/usr/bin/env ruby
# frozen_string_literal: true
require 'optparse'
require_relative 'xls_signature'

options = {}
OptionParser.new do |p|
  %w[signature output template width kind].each do |key|
    p.on("--#{key} VALUE") { |v| options[key] = v }
  end
end.parse!
text = File.read(options.fetch('signature'))
width = Integer(options.fetch('width'))
tick = options.fetch('kind') == 'tick'
ports = blocks(text, 'data_ports').to_h do |port|
  [scalar(port, 'name'), [scalar(port, 'direction'), Integer(scalar(port, 'width'))]]
end
expected_ports = {
  'crc' => ['PORT_DIRECTION_INPUT', 16],
  tick ? 'byte_input' : 'data' => ['PORT_DIRECTION_INPUT', width + (tick ? 1 : 0)],
  'out' => ['PORT_DIRECTION_OUTPUT', tick ? 33 : 16]
}
raise 'Unexpected CRC function interface' unless ports == expected_ports
pipeline = blocks(text, 'pipeline').first
latency = pipeline ? Integer(scalar(pipeline, 'latency')) : 0
raise 'Unsupported initiation interval' if pipeline && Integer(scalar(pipeline, 'initiation_interval')) != 1
connections = ['.crc(crc)', tick ? '.byte_input({data, last})' : '.data(data)', '.out(out)']
if pipeline
  connections << ".#{identifier(scalar(text, 'clock_name'))}(clk)"
  reset = blocks(text, 'reset').first
  raise 'Expected synchronous active-high reset' unless reset && scalar(reset, 'asynchronous') == 'false' && scalar(reset, 'active_low') == 'false'
  connections << ".#{identifier(scalar(reset, 'name'))}(rst)"
end
replacements = {
  '@WIDTH@' => width.to_s, '@OUT_WIDTH@' => (tick ? 33 : 16).to_s,
  '@LATENCY@' => latency.to_s,
  '@EXPECTED@' => tick ? '{(last ? 16\'b0 : reference), reference, last}' : 'reference',
  '@DUT@' => "#{identifier(scalar(text, 'module_name'))} dut(#{connections.join(', ')});"
}
output = File.read(options.fetch('template'))
replacements.each { |key, value| output = output.gsub(key, value) }
File.write(options.fetch('output'), output)
