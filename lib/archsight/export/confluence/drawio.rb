# frozen_string_literal: true

require "base64"
require "erb"
require "rexml/document"

module Archsight
  module Export
    module Confluence
      # draw.io files for the draw.io macro of Confluence.
      module Drawio
        DEFAULT_SIZE = [800, 600].freeze

        module_function

        # A draw.io file whose content is the SVG as an image shape (draw.io styles carry data URIs without
        # ";base64"), page-sized like the SVG. draw.io shows an SVG as a picture, so the links inside it are dead:
        # every linked shape of the SVG gets an invisible shape with the same link laid over it.
        # @return [String] mxfile XML
        def wrap_svg(svg, name)
          width, height = size(svg).map(&:ceil)
          data = Base64.strict_encode64(svg.sub(/\A<\?xml[^>]*\?>\s*/, ""))
          style = ERB::Util.html_escape("shape=image;imageAspect=0;aspect=fixed;verticalLabelPosition=bottom;verticalAlign=top;image=data:image/svg+xml,#{data};")
          id = ERB::Util.html_escape(name)
          cells = [%(<mxCell id="2" value="" style="#{style}" vertex="1" parent="1"><mxGeometry x="0" y="0" width="#{width}" height="#{height}" as="geometry"/></mxCell>)]
          link_areas(svg).each_with_index { |area, index| cells << link_cell(index + 3, area) }
          [
            %(<mxfile host="archsight"><diagram name="#{id}" id="#{id}"><mxGraphModel dx="0" dy="0" grid="0" guides="0" page="0" pageScale="1" ),
            %(pageWidth="#{width}" pageHeight="#{height}" math="0" shadow="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/>),
            cells.join,
            "</root></mxGraphModel></diagram></mxfile>\n"
          ].join
        end

        # The linked shapes of an SVG, outermost first (so nested ones end up on top).
        # @return [Array<Hash>] `{ url:, x:, y:, width:, height: }`
        def link_areas(svg)
          doc = REXML::Document.new(svg)
          REXML::XPath.match(doc, "//*[local-name()='a'][@href]").filter_map do |anchor|
            shape = anchor.elements.to_a.find { |element| element.name != "text" }
            box = shape && bounds(shape)
            { url: anchor.attributes["href"], **box } if box
          end
        rescue REXML::ParseException
          []
        end

        def link_cell(id, area)
          geometry = %(<mxGeometry x="#{area[:x].round(2)}" y="#{area[:y].round(2)}" width="#{area[:width].round(2)}" height="#{area[:height].round(2)}" as="geometry"/>)
          %(<UserObject label="" link="#{ERB::Util.html_escape(area[:url])}" id="#{id}"><mxCell style="fillColor=none;strokeColor=none;pointerEvents=1;" vertex="1" parent="1">#{geometry}</mxCell></UserObject>)
        end

        # x, y, width, height of a basic SVG shape, nil if it is not one we can measure
        def bounds(shape)
          number = ->(name) { shape.attributes[name].to_f }
          case shape.name
          when "rect" then { x: number.call("x"), y: number.call("y"), width: number.call("width"), height: number.call("height") }
          when "ellipse" then { x: number.call("cx") - number.call("rx"), y: number.call("cy") - number.call("ry"), width: 2 * number.call("rx"), height: 2 * number.call("ry") }
          when "circle" then { x: number.call("cx") - number.call("r"), y: number.call("cy") - number.call("r"), width: 2 * number.call("r"), height: 2 * number.call("r") }
          when "polygon", "path" then points_bounds(shape.attributes["points"] || shape.attributes["d"])
          end
        end

        # Extent of the coordinates in a polygon's points or a path's data (curve control points included, so
        # it can be a little larger than the shape)
        def points_bounds(data)
          pairs = data.to_s.scan(/-?\d+(?:\.\d+)?/).map(&:to_f).each_slice(2).select { |pair| pair.length == 2 }
          return nil if pairs.empty?

          xs = pairs.map(&:first)
          ys = pairs.map(&:last)
          { x: xs.min, y: ys.min, width: xs.max - xs.min, height: ys.max - ys.min }
        end

        # width and height of an SVG: its attributes, else its viewBox
        def size(svg)
          root = svg[/<svg\b[^>]*>/m].to_s
          width = root[/\swidth="([\d.]+)(?:px)?"/, 1]
          height = root[/\sheight="([\d.]+)(?:px)?"/, 1]
          return [width.to_f, height.to_f] if width && height

          box = root[/viewBox="([^"]+)"/, 1]&.split&.map(&:to_f)
          box && box.length == 4 ? [box[2], box[3]] : DEFAULT_SIZE
        end

        # The draw.io macro for a diagram attached as `name` (+ `name.png`)
        def macro(name)
          params = { "border" => "true", "viewerToolbar" => "true", "fitWindow" => "false", "diagramName" => name,
                     "simpleViewer" => "false", "tbstyle" => "top", "lbox" => "true", "revision" => "1" }
          inner = params.map { |key, value| %(<ac:parameter ac:name="#{key}">#{ERB::Util.html_escape(value)}</ac:parameter>) }.join
          %(<ac:structured-macro ac:name="drawio" ac:schema-version="1">#{inner}</ac:structured-macro>\n)
        end
      end
    end
  end
end
