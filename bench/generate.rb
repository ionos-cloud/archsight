# frozen_string_literal: true

# Emits a synthetic, deterministic Archsight::Diagram diagram for benchmarking:
# `groups` groups of `per_group` nodes each, ~1.2 random edges per node
# and one 4-hop dataflow per 20 nodes.
#
#   ruby bench/generate.rb GROUPS PER_GROUP > big.asd
module BenchDiagram
  module_function

  def source(groups, per_group, seed: 42)
    rng = Random.new(seed)
    ids = []
    out = +"layer {\n"
    groups.times do |i|
      out << "  #{i.even? ? "stack" : "layer"} {\n    group \"g#{i}\" {\n      label \"Group #{i}\"\n      layer {\n"
      per_group.times do |j|
        id = "n#{i}_#{j}"
        ids << id
        out << "        application \"#{id}\" { label \"Node #{i}.#{j}\" }\n"
      end
      out << "      }\n    }\n  }\n"
    end
    out << "}\n"
    (ids.size * 1.2).to_i.times do
      a, b = ids.sample(2, random: rng)
      out << "#{a} -> #{b} { label \"e\" }\n"
    end
    (ids.size / 20).times do |k|
      out << "dataflow \"df#{k}\" {\n"
      ids.sample(4, random: rng).each { |h| out << "  hop \"#{h}\"\n" }
      out << "  label \"f#{k}\"\n}\n"
    end
    out
  end
end

puts BenchDiagram.source(Integer(ARGV.fetch(0)), Integer(ARGV.fetch(1))) if $PROGRAM_NAME == __FILE__
