# frozen_string_literal: true

require "erb"
require_relative "../../page_tree"

module Archsight
  module Helpers
    module Macros
      # `{children}`: the child pages of the page it is on, like the children macro of Confluence. The children of a
      # page are the contents of the PageMenu that opens it (see PageTree#children).
      #
      # Options, separated by spaces: `depth=N` (levels, default 1), `all` (every level), `sort=title` (default: the
      # order of the menu), `reverse`.
      module Children
        Options = Struct.new(:depth, :order, :reverse)
        EMPTY = %(<div class="macro-children-empty macro-block">No child pages</div>)

        class << self
          def block? = true

          # @return [Options, nil] nil for an unknown option or a bad value
          def parse(arguments)
            options = Options.new(1, nil, false)
            arguments.to_s.split.each do |word|
              key, value = word.split("=", 2)
              return nil unless apply(options, key, value)
            end
            options
          end

          def problem(arguments, _context = nil)
            "expected options from: depth=N, all, sort=title, reverse" unless parse(arguments)
          end

          # @param context [Macros::Context, nil] without the page there is nothing to list
          def html(options, context = nil)
            page = context&.page
            return nil unless page && context.database

            entries = PageTree.new(context.database).children(page, depth: options.depth, sort: options.order, reverse: options.reverse)
            entries.empty? ? EMPTY : list(entries, "macro-children macro-block")
          end

          def confluence(options, _context = nil)
            parameters = []
            parameters << parameter("all", "true") if options.depth == Float::INFINITY
            parameters << parameter("depth", options.depth) if options.depth.is_a?(Integer) && options.depth > 1
            parameters << parameter("sort", "title") if options.order
            parameters << parameter("reverse", "true") if options.reverse
            %(<ac:structured-macro ac:name="children">#{parameters.join}</ac:structured-macro>)
          end

          # The nested list of entries (`{ "name", "title", "children" }`) as HTML
          def list(entries, css = nil)
            items = entries.map do |entry|
              title = ERB::Util.html_escape(entry["title"])
              label = entry["name"] ? %(<a href="/pages/#{ERB::Util.url_encode(entry["name"])}">#{title}</a>) : title
              nested = entry["children"].empty? ? "" : list(entry["children"])
              "<li>#{label}#{nested}</li>"
            end
            %(<ul#{%( class="#{css}") if css}>#{items.join}</ul>)
          end

          private

          def apply(options, key, value)
            case key
            when "all" then value.nil? && (options.depth = Float::INFINITY)
            when "reverse" then value.nil? && (options.reverse = true)
            when "sort" then value == "title" && (options.order = value)
            when "depth" then value.to_s.match?(/\A[1-9]\d{0,2}\z/) && (options.depth = value.to_i)
            else false
            end
          end

          def parameter(name, value) = %(<ac:parameter ac:name="#{name}">#{value}</ac:parameter>)
        end
      end

      # `{pagetree}`: the tree below a page, the page itself on top, like the page tree macro of Confluence.
      #
      # Options, separated by spaces: `root=PAGE` (a page name, default: the page the macro is on), `sort=title`, `reverse`.
      module Pagetree
        Options = Struct.new(:root, :order, :reverse)

        class << self
          def block? = true

          # @return [Options, nil] nil for an unknown option or a bad value
          def parse(arguments)
            options = Options.new(nil, nil, false)
            arguments.to_s.split.each do |word|
              key, value = word.split("=", 2)
              return nil unless apply(options, key, value)
            end
            options
          end

          def problem(arguments, context = nil)
            options = parse(arguments)
            return "expected options from: root=PAGE, sort=title, reverse" unless options
            return unless options.root && context&.database && !context.database.instances_by_kind("Page").key?(options.root)

            "there is no page named #{options.root.inspect}"
          end

          def html(options, context = nil)
            root = root_page(options, context)
            return nil unless root

            entries = PageTree.new(context.database).children(root, depth: Float::INFINITY, sort: options.order, reverse: options.reverse)
            Children.list([{ "name" => root.name, "title" => root.title, "children" => entries }], "macro-children macro-pagetree macro-block")
          end

          def confluence(options, context = nil)
            title = options.root ? (page_of(options.root, context)&.title || options.root) : "@self"
            parameters = [parameter("root", title)]
            parameters << parameter("sort", "title") if options.order
            parameters << parameter("reverse", "true") if options.reverse
            %(<ac:structured-macro ac:name="pagetree">#{parameters.join}</ac:structured-macro>)
          end

          private

          def apply(options, key, value)
            case key
            when "reverse" then value.nil? && (options.reverse = true)
            when "sort" then value == "title" && (options.order = value)
            when "root" then value.to_s.match?(/\A[^\s=]+\z/) && (options.root = value)
            else false
            end
          end

          def root_page(options, context)
            return nil unless context&.database

            options.root ? page_of(options.root, context) : context.page
          end

          def page_of(name, context)
            pages = context&.database&.instances_by_kind("Page")
            pages && pages[name]
          end

          def parameter(name, value) = %(<ac:parameter ac:name="#{name}">#{ERB::Util.html_escape(value)}</ac:parameter>)
        end
      end

      register("children", Children)
      register("pagetree", Pagetree)
    end
  end
end
