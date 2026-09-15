#!/usr/bin/env ruby
require 'optparse'
require 'fileutils'

options = {}
OptionParser.new do |parser|
  parser.on('--output DIR') { |value| options[:output] = value }
  parser.on('--rtl FILE') { |value| options[:rtl] = value }
  parser.on('--top NAME') { |value| options[:top] = value }
  parser.on('--period-ps PS', Integer) { |value| options[:period_ps] = value }
end.parse!

required = %i[output rtl top period_ps]
missing = required.reject { |key| options.key?(key) }
abort "missing options: #{missing.join(', ')}" unless missing.empty?
abort '--period-ps must be positive' unless options[:period_ps].positive?
output = File.expand_path(options[:output])
rtl = File.expand_path(options[:rtl])
abort "RTL not found: #{rtl}" unless File.file?(rtl)
FileUtils.mkdir_p(output)
period_ns = format('%.3f', options[:period_ps] / 1000.0)
File.write(File.join(output, 'constraint.sdc'), "create_clock -name clk -period #{period_ns} [get_ports clk]\n")
File.write(File.join(output, 'config.mk'), <<~CONFIG)
  export PLATFORM = asap7
  export DESIGN_NAME = #{options[:top]}
  export VERILOG_FILES = #{rtl}
  export SDC_FILE = #{File.join(output, 'constraint.sdc')}
  export CORE_UTILIZATION = 60
  export CORE_ASPECT_RATIO = 1
  export CORE_MARGIN = 1
  export PLACE_DENSITY = 0.60
CONFIG
