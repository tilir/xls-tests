#!/usr/bin/env ruby
# frozen_string_literal: true

# Prove equality of XOR-only combinational Yosys JSON netlists.
# Tracks each wire as an affine GF(2) expression of named input bits. Equality
# of output expressions proves equality for every input, without sampling.
# Also reports unit-gate depth (not technology-mapped timing).
# Usage: compare_crc_netlists.rb reference.json candidate.json
require 'json'
require 'set'

def analyze(path)
  modules = JSON.parse(File.read(path)).fetch('modules')
  raise 'Expected one flattened module' unless modules.length == 1

  mod = modules.values.first
  values = { '0' => Set.new, '1' => Set[:constant_one] }
  depth = { '0' => 0, '1' => 0 }
  inputs = {}
  mod.fetch('ports').each do |name, port|
    next unless port.fetch('direction') == 'input'

    inputs[name] = port.fetch('bits').length
    port.fetch('bits').each_with_index do |bit, i|
      values[bit] = Set[[name, i]]
      depth[bit] = 0
    end
  end
  pending = mod.fetch('cells').values.dup
  until pending.empty?
    progress = false
    pending.dup.each do |cell|
      kind = cell.fetch('type')
      raise "Unsupported cell: #{kind}" unless %w[$_XOR_ $_XNOR_ $_NOT_ $_BUF_].include?(kind)

      pins = cell.fetch('connections')
      sources = pins.fetch('A') + pins.fetch('B', [])
      next unless sources.all? { |bit| values.key?(bit) }

      result = sources.reduce(Set.new) { |accum, bit| accum ^ values.fetch(bit) }
      result ^= values.fetch('1') if %w[$_XNOR_ $_NOT_].include?(kind)
      raise 'Expected one output bit per cell' unless pins.fetch('Y').length == 1

      output = pins.fetch('Y').first
      values[output] = result
      depth[output] = 1 + sources.map { |bit| depth.fetch(bit) }.max
      pending.delete(cell)
      progress = true
    end
    raise 'Unresolved net or combinational cycle' unless progress
  end
  output_ports = mod.fetch('ports').select { |_, port| port.fetch('direction') == 'output' }
  outputs = output_ports.transform_values { |port| port.fetch('bits').map { |bit| values.fetch(bit) } }
  longest = output_ports.values.flat_map { |port| port.fetch('bits').map { |bit| depth.fetch(bit) } }.max
  puts "#{path}: #{mod.fetch('cells').length} cells, #{longest} gate levels"
  [inputs, outputs]
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} reference.json candidate.json" unless ARGV.length == 2
  reference = analyze(ARGV[0])
  candidate = analyze(ARGV[1])
  abort 'FAIL: interfaces or output functions differ' unless reference == candidate
  puts 'PASS: identical affine output functions for every input'
end
