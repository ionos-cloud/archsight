# frozen_string_literal: true

require "open3"
require "tmpdir"

module Archsight
  module Export
    module Confluence
      # PNG renderings made by tools installed on the machine that exports: rsvg-convert for SVG, the draw.io
      # desktop CLI (`drawio`) for diagrams. A missing tool is `nil`, not an exception; the caller decides.
      module Rasterizer
        module_function

        # @return [String, nil] PNG bytes of an SVG document, nil without rsvg-convert
        def svg_to_png(svg)
          out, status = Open3.capture2("rsvg-convert", "--format", "png", "--background-color", "white", "--zoom", "2",
                                       stdin_data: svg, binmode: true)
          status.success? ? out : nil
        rescue Errno::ENOENT
          nil
        end

        # @return [String, nil] PNG bytes of a draw.io file's first page, nil without the draw.io CLI or when it fails
        def drawio_to_png(xml, command: ENV.fetch("ARCHSIGHT_DRAWIO_CLI", "drawio"))
          Dir.mktmpdir("archsight-drawio") do |dir|
            input = File.join(dir, "in.drawio")
            output = File.join(dir, "out.png")
            File.write(input, xml)
            _out, _err, status = Open3.capture3(command, "--export", "--format", "png", "--output", output, input)
            status.success? && File.file?(output) ? File.binread(output) : nil
          end
        rescue Errno::ENOENT
          nil
        end
      end
    end
  end
end
