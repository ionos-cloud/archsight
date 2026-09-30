# frozen_string_literal: true

require "kramdown"
require_relative "helpers"

module Archsight
  class Linter
    # Valid @component references in View annotations
    VALID_COMPONENTS = %w[activity git jira languages owner repositories status].freeze

    def initialize(database)
      @database = database
      @errors = []
    end

    def validate
      @database.instances.each_value do |instances_hash|
        instances_hash.each_value do |instance|
          validate_instance_annotations(instance)
          validate_view_fields(instance) if instance.klass == "View"
          validate_page(instance) if instance.klass == "Page"
          validate_menu_cycle(instance) if instance.klass == "PageMenu"
        end
      end

      @errors
    end

    private

    # Pages need exactly one menu and their [[links]] must resolve
    def validate_page(page)
      menus = page.references.map { |r| r[:instance] }.select { |i| i.klass == "PageMenu" }.uniq
      @errors << "#{page.path_ref}: Page '#{page.name}' is not contained in any PageMenu" if menus.empty? && !page.home?
      @errors << "#{page.path_ref}: Page '#{page.name}' is contained in several PageMenus (#{menus.map(&:name).join(", ")})" if menus.length > 1

      links = Archsight::Helpers::WikiLinks.new(@database)
      page.annotations["page/content"].to_s.scan(Archsight::Helpers::WikiLinks::PATTERN).map { |match| match.first.strip }.each do |target|
        next if links.resolve(target).is_a?(String)

        @errors << "#{page.path_ref}: Page '#{page.name}' links to unknown or ambiguous [[#{target}]]"
      end
    end

    # A PageMenu must not (transitively) contain itself
    def validate_menu_cycle(menu)
      cycle = find_menu_cycle(menu, menu, [menu.name], [])
      @errors << "#{menu.path_ref}: PageMenu '#{menu.name}' forms a cycle (#{cycle.join(" -> ")})" if cycle
    end

    def find_menu_cycle(origin, current, path, visited)
      current.relations(:contains, :menus).each do |child|
        return path + [child.name] if child.equal?(origin)
        next if visited.include?(child.name)

        visited << child.name
        found = find_menu_cycle(origin, child, path + [child.name], visited)
        return found if found
      end
      nil
    end

    def validate_instance_annotations(instance)
      instance.annotations.each do |key, value|
        # Find matching annotation definition (handles both exact and pattern matches)
        annotation = instance.class.annotation_matching(key)

        if annotation.nil?
          @errors << "#{instance.path_ref}: Unknown annotation '#{key}' for #{instance.klass}"
          next
        end

        # Content checks don't depend on enum/type constraints
        validate_markdown(instance, key, value) if annotation.markdown?
        validate_diagram(instance, key, value) if annotation.diagram?

        # Skip schema validation if annotation has no constraints (enum or type)
        next unless annotation.has_validation?

        # Validate value against annotation schema (type and enum constraints)
        annotation.validate(value).each do |error|
          @errors << "#{instance.path_ref}: Annotation '#{key}' #{error}"
        end
      end
    end

    def validate_markdown(instance, key, value)
      # Skip markdown validation for generated files
      return if instance.annotations.key?("generated/script")

      begin
        Kramdown::Document.new(value, input: "GFM")
      rescue StandardError => e
        @errors << "#{instance.path_ref}: Markdown syntax error in annotation '#{key}': #{e.message}"
      end
      validate_diagram_blocks(instance, key, value)
    end

    # A diagram annotation must render, or the page shows an error box instead of the diagram
    def validate_diagram(instance, key, value)
      return if instance.annotations.key?("generated/script")

      render_diagram_source(instance, "annotation '#{key}'", value.to_s)
    end

    # Every ```asd block must render, or the page shows an error box instead of the diagram
    def validate_diagram_blocks(instance, key, value)
      Helpers::DiagramBlocks.sources(value).each_with_index do |source, index|
        render_diagram_source(instance, "annotation '#{key}' (asd block #{index + 1})", source)
      end
    end

    # Renders with the same resolver the web UI uses, so a `resource` reference that would show as a broken link there is reported here
    def render_diagram_source(instance, where, source)
      unresolved = []
      Archsight::Diagram.render(source, resolver: Helpers::ResourceResolver.new(@database), unresolved: unresolved)
      unresolved.each do |u|
        @errors << "#{instance.path_ref}: Diagram resource link #{u[:reference].inspect} #{u[:reason]} in #{where} (node #{u[:node].inspect}, line #{u[:line]})"
      end
    rescue Archsight::Diagram::Error => e
      @errors << "#{instance.path_ref}: Diagram error in #{where}: #{e.message}"
    end

    def validate_view_fields(instance)
      fields = instance.annotations["view/fields"]
      return unless fields

      fields.split(",").map(&:strip).each do |field|
        next unless field.start_with?("@")

        component_name = field[1..]
        unless VALID_COMPONENTS.include?(component_name)
          @errors << "#{instance.path_ref}: Unknown view component '@#{component_name}'. " \
                     "Valid components: #{VALID_COMPONENTS.map { |c| "@#{c}" }.join(", ")}"
        end
      end
    end
  end
end
