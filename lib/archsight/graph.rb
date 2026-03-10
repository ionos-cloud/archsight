# frozen_string_literal: true

module Archsight
  # Graphvis implements a graphviz abstraction
  class Graphvis
    def initialize(name, attrs = {})
      @name = name
      @attrs = { rankdir: :LR }.merge(attrs)
    end

    def draw_dot(&)
      f = StringIO.new
      render(f, &)
      f.string
    end

    def render(file)
      @file = file
      file.puts "digraph G {"
      @attrs.each do |k, v|
        @file.puts " #{k.to_s.inspect} = #{value v};"
      end
      yield(self)
      file.puts "}"
    end

    def node(name, attrs = {})
      @file.print "  #{name.inspect} ["
      attrs.each do |k, v|
        @file.print " #{k.to_s.inspect} = #{value v}"
      end
      @file.puts " ];"
    end

    def edge(node_a, node_b, attrs = {})
      @file.print "  #{node_a.inspect} -> #{node_b.inspect} ["
      attrs.each do |k, v|
        @file.print " #{k.to_s.inspect} = #{value v}"
      end
      @file.puts " ];"
    end

    def subgraph(name, attrs)
      @file.puts "  subgraph #{name.inspect} {"
      attrs.each do |k, v|
        @file.puts " #{k.to_s.inspect} = #{value v};"
      end
      yield(self)
      @file.puts "  }"
    end

    def value(val)
      val = val.to_s
      val =~ /^<.*>$/ ? "<#{val}>" : val.inspect
    end

    def same_rank
      @file.puts "  { rank = same; "
      yield(self)
      @file.puts "  }"
    end
  end
end
