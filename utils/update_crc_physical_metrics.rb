#!/usr/bin/env ruby
# Adds final-stage ORFS metrics to the CRC analysis CSV.
require 'csv'
require 'json'

csv_path = ARGV.fetch(0, 'reports/sep-15-2026/crc_metrics.csv')
orfs_root = ARGV.fetch(1, 'build1000/crc/openroad')

columns = %w[
  physical_flow physical_platform physical_corner physical_target_period_ps
  physical_instances physical_stdcell_area_um2 physical_utilization
  physical_setup_wns_ps physical_setup_tns_ps physical_setup_violations
  physical_flow_errors physical_status
]

metrics = Dir.glob(File.join(orfs_root, '*', 'logs', 'asap7', '*', 'base',
                             '6_report.json')).each_with_object({}) do |path, result|
  report = JSON.parse(File.read(path))
  target = path.split('/')[3]
  result[target] = {
    'physical_flow' => 'ORFS',
    'physical_platform' => 'ASAP7',
    'physical_corner' => 'BC / NLDM',
    'physical_target_period_ps' => '1000',
    'physical_instances' => report.fetch('finish__design__instance__count').to_s,
    'physical_stdcell_area_um2' => report.fetch('finish__design__instance__area__stdcell').to_s,
    'physical_utilization' => report.fetch('finish__design__instance__utilization').to_s,
    'physical_setup_wns_ps' => report.fetch('finish__timing__setup__ws').to_s,
    'physical_setup_tns_ps' => report.fetch('finish__timing__setup__tns').to_s,
    'physical_setup_violations' => report.fetch('finish__timing__drv__setup_violation_count').to_s,
    'physical_flow_errors' => report.fetch('finish__flow__errors__count').to_s,
    'physical_status' => report.fetch('finish__timing__setup__ws').negative? ? 'setup-fail' : 'closed'
  }
end

table = CSV.read(csv_path, headers: true)
headers = table.headers | columns
CSV.open(csv_path, 'w') do |csv|
  csv << headers
  table.each do |row|
    values = headers.to_h { |column| [column, row[column]] }
    values.merge!(metrics.fetch(row['target'], {})) if row['build'] == '1000'
    csv << headers.map { |column| values[column] }
  end
end
