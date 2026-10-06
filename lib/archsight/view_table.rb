# frozen_string_literal: true

module Archsight
  # The result of a view as a plain table (columns and rows of text), for places that cannot run the frontend, such
  # as the Confluence export. It follows what the web UI shows for a View (`ViewResults.vue`, `ResourceList.vue`):
  # a Name column, a Kind column unless the view is `list:name`, one column per `view/fields` entry that is not
  # `name` or `kind`, rows sorted by `view/sort`.
  module ViewTable
    # Rows beyond this are cut (the table says how many); a Confluence page is no place for thousands of rows
    LIMIT = 200

    # @param as [Symbol] :text, :status or :priority (a requirement's, shown as a lozenge) or :markdown
    # @param resources [Array] resources the cell names (shown one per line, linked where a target exists)
    Cell = Struct.new(:text, :resources, :as, keyword_init: true) do
      def initialize(text: "", resources: [], as: :text) = super
    end

    # @param title [String] shown above the table, may be empty
    # @param columns [Array<String>] header texts
    # @param rows [Array<Array<Cell>>] at most LIMIT
    # @param total [Integer] number of rows before cutting
    Table = Struct.new(:title, :columns, :rows, :total, keyword_init: true) do
      def cut = total - rows.length
    end

    IDENTITY_FIELDS = %w[name kind].freeze

    module_function

    # @raise [Archsight::Query::QueryError] if the query does not parse
    def build(database, query:, fields: [], sort: [], show_kind: true, title: "", limit: LIMIT)
      resources = sort_resources(Archsight::Query.parse(query).filter(database), sort)
      columns = fields.reject { |f| IDENTITY_FIELDS.include?(f) }
      header = ["Name", (show_kind ? "Kind" : nil), *columns.map { |f| column_title(f) }].compact
      rows = resources.first(limit).map do |resource|
        [Cell.new(text: resource.name, resources: [resource]),
         (Cell.new(text: kind_of(resource)) if show_kind),
         *columns.map { |f| Cell.new(text: resource.annotations[f].to_s) }].compact
      end
      Table.new(title: title, columns: header, rows: rows, total: resources.length)
    end

    # The table of a ```view block (see Helpers::ViewBlocks)
    # @raise [Helpers::ViewBlocks::Error, Archsight::Query::QueryError]
    def from_block(database, source)
      spec = Helpers::ViewBlocks.parse(source)
      build(database, query: spec[:query], fields: spec[:fields], sort: spec[:sort], show_kind: spec[:type] == "list:name+kind", title: spec[:title])
    end

    # The table of a View resource
    # @raise [Helpers::ViewBlocks::Error, Archsight::Query::QueryError]
    def from_view(database, view)
      annotations = view.annotations
      query = annotations["view/query"].to_s.strip
      raise Helpers::ViewBlocks::Error, "view #{view.name} has no query" if query.empty?

      build(database, query: query, fields: list(annotations["view/fields"]), sort: list(annotations["view/sort"]),
                      show_kind: (annotations["view/type"] || "list:name+kind") == "list:name+kind", title: view.name)
    end

    # "scc/language/Go/loc" -> "Go loc", "activity/createdAt" -> "Activity created At" (as ResourceList.vue titles columns)
    def column_title(key)
      segments = key.split("/")
      title = segments.length >= 2 ? "#{segments[-2]} #{segments[-1]}" : segments.last.to_s
      title.gsub(/([a-z])([A-Z])/, '\1 \2').sub(/\A./, &:upcase)
    end

    def kind_of(resource) = resource.class.name.split("::").last

    def list(value) = value.to_s.split(",").map(&:strip).reject(&:empty?)

    # `view/sort` fields: name, kind or an annotation, "-" for descending; numbers inside text compare as numbers.
    # Without a sort the order is by name, like the search API.
    def sort_resources(resources, sort)
      return resources.sort_by(&:name) if sort.empty?

      resources.sort { |left, right| compare(left, right, sort) }
    end

    def compare(left, right, sort)
      sort.each do |field|
        key = field.delete_prefix("-")
        order = natural(value_of(left, key)) <=> natural(value_of(right, key))
        return field.start_with?("-") ? -order : order unless order.zero?
      end
      0
    end

    def value_of(resource, key)
      case key
      when "name" then resource.name
      when "kind" then kind_of(resource)
      else resource.annotations[key].to_s
      end
    end

    # A key for sorting text with numbers in it the way people expect (item2 < item10, case-insensitive first)
    def natural(text)
      [text.scan(/\d+|\D+/).map { |part| part.match?(/\A\d/) ? [0, part.to_i] : [1, part.downcase] }, text]
    end
  end
end
