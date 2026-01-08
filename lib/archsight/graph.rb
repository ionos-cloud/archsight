# frozen_string_literal: true

module Archsight
  # Graphvis implements a graphviz abstraction
  class Graphvis
    def initialize(name, renderer = :dot, attrs = {})
      @name = name
      @renderer = renderer.to_s
      @attrs = { rankdir: :LR }.merge(attrs)
    end

    def draw_and_render_file(&block)
      File.open("#{@name}.dot", "w") do |f|
        render(f, &block)
      end
      system "#{@renderer} -Tpng #{@name}.dot -o #{@name}.png"
    end

    def draw_dot(&)
      f = StringIO.new
      render(f, &)
      f.string
    end

    def draw_svg(&block)
      IO.popen([@renderer, "-Tsvg"], "r+") do |pipe|
        render(pipe, &block)
        pipe.close_write
        pipe.read
      end
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

  # GraphvisHelper for generating graphs using javascript and wasm
  module GraphvisHelper
    def graphviz_svg(dot, element_id)
      format(%{
        <script type="module">
          import { Graphviz } from "https://cdn.jsdelivr.net/npm/@hpcc-js/wasm/dist/index.js";
          if (Graphviz) {
            const re =/<svg width="([^"]+)pt" height="([^"]+)pt"/;
            const graphviz = await Graphviz.load();
            const dot = %s;
            let svg = graphviz.layout(dot, "svg", "dot");
            svg = svg.replace(re, "<svg");
            svg = svg.replace(/<polygon fill="white"[^>]*>/, "");
            svg = svg.replace(/fill="white"/g, 'fill="none"');

            const parser = new DOMParser();
            const svgDoc = parser.parseFromString(svg, "image/svg+xml");
            const svgElement = svgDoc.querySelector("svg");

            const cssResponse = await fetch("/css/graph.css?" + Date.now());
            const cssText = await cssResponse.text();
            const style = document.createElementNS("http://www.w3.org/2000/svg", "style");
            style.textContent = cssText;
            svgElement.insertBefore(style, svgElement.firstChild);

            document.getElementById(%s).innerHTML = svgElement.outerHTML;
            // Dispatch event to notify GraphViewer that SVG is ready
            document.dispatchEvent(new CustomEvent('graphviz:ready', { detail: { elementId: %s } }));
          }
        </script>
      }, dot.inspect, element_id.inspect, element_id.inspect)
    end
  end
end
