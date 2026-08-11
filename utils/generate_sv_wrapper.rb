#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates a stable ready/valid SV wrapper from an XLS module signature.
#
# codegen_main writes the input as a ModuleSignatureProto textproto. In the
# subset used here it contains the generated module/clock/reset names, a list
# of physical data ports and one channel_interfaces entry per DSLX channel:
#
#   module_name: "crc16"
#   clock_name: "clk"
#   reset { name: "rst" }
#   channel_interfaces {
#     channel_name: "_input"
#     direction: CHANNEL_DIRECTION_RECEIVE
#     streaming {
#       data_port_name: "_input"
#       ready_port_name: "_input_rdy"
#       valid_port_name: "_input_vld"
#     }
#   }
#
# The generated simulation-only module instantiates that implementation and
# exposes a stable testbench-facing convention. Leading underscores are removed
# from channel names, and each channel becomes <name>_data, <name>_valid, and
# <name>_ready; clock and reset are exposed literally as `clock` and `reset`.
# Thus changes to XLS physical port naming remain isolated in this generated
# adapter and do not leak into hand-written testbenches.
#
# Only streaming ready/valid channels are supported intentionally. Encountering
# another interface kind is an error instead of silently generating bad wiring.

require "optparse"
require "set"
require "fileutils"

def blocks(text, field)
  result = []
  pattern = /^\s*#{Regexp.escape(field)}\s*\{/
  offset = 0

  while (match = pattern.match(text, offset))
    start = match.end(0)
    depth = 1
    index = start
    while index < text.length && depth.positive?
      depth += 1 if text.getbyte(index) == "{".ord
      depth -= 1 if text.getbyte(index) == "}".ord
      index += 1
    end
    raise "unterminated #{field} block" unless depth.zero?

    result << text[start...(index - 1)]
    offset = index
  end
  result
end

def scalar(text, field)
  pattern = /^\s*#{Regexp.escape(field)}:\s*(?:"([^"]*)"|([^\s#]+))/
  match = pattern.match(text)
  raise "missing #{field}" unless match

  match[1] || match[2]
end

def identifier(name)
  return name if name.match?(/\A[A-Za-z_][A-Za-z0-9_$]*\z/)

  "\\#{name} "
end

def stable_name(name)
  result = name.sub(/\A_+/, "").gsub(/[^A-Za-z0-9_]/, "_")
  raise "channel name #{name.inspect} has no usable characters" if result.empty?

  result = "channel_#{result}" if result.match?(/\A[0-9]/)
  result
end


options = {}
OptionParser.new do |parser|
  parser.on("--signature PATH") { |value| options[:signature] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--module NAME") { |value| options[:module] = value }
end.parse!

missing = %i[signature output module].reject { |key| options.key?(key) }
raise "missing options: #{missing.join(', ')}" unless missing.empty?

text = File.read(options[:signature], encoding: "UTF-8")
implementation = scalar(text, "module_name")
clock = scalar(text, "clock_name")
reset_blocks = blocks(text, "reset")
reset = scalar(reset_blocks.first, "name") unless reset_blocks.empty?

widths = blocks(text, "data_ports").to_h do |port|
  [scalar(port, "name"), Integer(scalar(port, "width"), 10)]
end

ports = [["input", 1, "clock"]]
connections = [[clock, "clock"]]
if reset
  ports << ["input", 1, "reset"]
  connections << [reset, "reset"]
end

used_names = ports.map(&:last).to_set
blocks(text, "channel_interfaces").each do |channel|
  stream = blocks(channel, "streaming").first
  raise "only streaming channel interfaces are supported" unless stream

  direction = scalar(channel, "direction")
  base = stable_name(scalar(channel, "channel_name"))
  data_port = scalar(stream, "data_port_name")
  ready_port = scalar(stream, "ready_port_name")
  valid_port = scalar(stream, "valid_port_name")
  stable_ports = ["#{base}_data", "#{base}_valid", "#{base}_ready"]
  raise "duplicate stable channel name #{base.inspect}" unless
    used_names.intersection(stable_ports).empty?

  used_names.merge(stable_ports)
  width = widths.fetch(data_port)
  case direction
  when "CHANNEL_DIRECTION_RECEIVE"
    ports.concat([
      ["input", width, stable_ports[0]],
      ["input", 1, stable_ports[1]],
      ["output", 1, stable_ports[2]]
    ])
  when "CHANNEL_DIRECTION_SEND"
    ports.concat([
      ["output", width, stable_ports[0]],
      ["output", 1, stable_ports[1]],
      ["input", 1, stable_ports[2]]
    ])
  else
    raise "unsupported channel direction #{direction}"
  end
  connections.concat([
    [data_port, stable_ports[0]],
    [valid_port, stable_ports[1]],
    [ready_port, stable_ports[2]]
  ])
end

declarations = ports.map do |direction, width, name|
  width_text = width == 1 ? "" : " [#{width - 1}:0]"
  "  #{direction} wire#{width_text} #{name}"
end
connection_text = connections.map do |actual, stable|
  "    .#{identifier(actual)}(#{stable})"
end.join(",\n")

output = <<~SYSTEM_VERILOG
  // Generated from the XLS module signature; do not edit.
  module #{identifier(options[:module])}(
  #{declarations.join(",\n")}
  );
    #{identifier(implementation)} implementation (
  #{connection_text}
    );
  endmodule
SYSTEM_VERILOG

FileUtils.mkdir_p(File.dirname(options[:output])) unless File.dirname(options[:output]) == "."
File.write(options[:output], output, encoding: "UTF-8")
