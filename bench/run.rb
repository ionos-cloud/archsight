# frozen_string_literal: true

# Renders synthetic diagrams of increasing size and prints per-stage
# timings (see `Archsight::Diagram.render`'s `profile:`).
#
#   ruby bench/run.rb [GROUPSxPER_GROUP ...]   (default: 5x5 10x5 10x10 20x10)
#   ARCHSIGHT_DIAGRAM_NATIVE=0 ruby bench/run.rb          (force the pure-Ruby backend)
#   ruby bench/run.rb --out DIR                (also write each SVG into DIR)
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "archsight/diagram"
require_relative "generate"

out_dir = (i = ARGV.index("--out")) ? ARGV.slice!(i, 2).last : nil
sizes = (ARGV.empty? ? %w[5x5 10x5 10x10 20x10] : ARGV).map { |s| s.split("x").map { |n| Integer(n) } }

puts "backend: #{Archsight::Diagram::Native.available? ? "native" : "ruby"}"
sizes.each do |groups, per_group|
  profile = {}
  svg = Archsight::Diagram.render(BenchDiagram.source(groups, per_group), profile: profile)
  File.write(File.join(out_dir, "#{groups}x#{per_group}.svg"), svg) if out_dir
  stages = profile.map { |k, v| format("%s=%.1fms", k, v * 1000) }.join(" ")
  puts format("%4d nodes  total=%8.1fms  %s", groups * per_group, profile.values.sum * 1000, stages)
end
