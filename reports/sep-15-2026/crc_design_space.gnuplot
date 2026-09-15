# Run from this directory: gnuplot crc_design_space.gnuplot
# Inputs are transcribed from crc_metrics.csv. Counts are generic Yosys
# synth -flatten cells; they are structural counts, not technology-mapped area.
set terminal pngcairo size 1400,1000 font "Sans,18"
set encoding utf8
set border 3
set grid ytics
set style fill solid 0.85 border -1
set style data histograms
set boxwidth 0.82

$composition << EOD
"stream"       16  44
"folded"      131 224
"naive C"       0 385
"naive P 2ns" 217 387
"naive P 1ns" 340 390
"opt C"         0 438
"opt P"       160 438
"tick"          0  42
EOD

set output "crc_yosys_cell_composition.png"
set bmargin 10
set key at graph 0.5, graph -0.16 center top horizontal
set style histogram rowstacked
set title "Generic Yosys cell composition"
set ylabel "generic cells"
set yrange [0:800]
set xtics rotate by 0 center font ",12"
plot $composition using 2:xtic(1) title "sequential" lc rgb "#2e8b57", \
     '' using 3 title "combinational" lc rgb "#c73e3a"
unset label 1

$stages << EOD
"naive"     4 2
"optimized" 1 1
EOD

set output "crc_compute_stages.png"
set bmargin 10
set key at graph 0.5, graph -0.16 center top horizontal
set style histogram clustered gap 1
set title "CRC compute stages selected by XLS"
set ylabel "combinational compute intervals"
set yrange [0:5]
set xtics rotate by 0 font ",13"
set label 2 "Signature latency: naive 5 / 3 cycles; optimized 2 / 2 cycles.  II = 1." \
  at graph 0.02, graph 0.95 front font ",12"
plot $stages using 2:xtic(1) title "1000 ps" lc rgb "#c73e3a", \
     '' using 3 title "2000 ps" lc rgb "#2e8b57"
unset label 2
