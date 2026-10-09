# frozen_string_literal: true

require "kramdown"
require_relative "helpers"

module Archsight
  class Linter
    # Valid @component references in View annotations
    VALID_COMPONENTS = %w[activity git jira languages owner repositories status].freeze

    # Relations the cycle check leaves out. Relations are followed from the dependent to what it relies on, so
    # the declared ones form a DAG; `dependsOn` is the exception because components may depend on each other at
    # runtime. The derived relations (`mentions`, `depicts`) are sideways views and are not declared, so they
    # never enter the check.
    CYCLE_EXEMPT_VERBS = %i[dependsOn].freeze

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
          validate_menu(instance) if instance.klass == "PageMenu"
        end
      end
      validate_relation_cycles
      validate_unique_annotations

      @errors
    end

    # Things that still work but should be changed: renamed kinds and relation keys that the files still use.
    # They are not errors, so they do not make `archsight lint` fail.
    def warnings
      @database.respond_to?(:deprecations) ? @database.deprecations.map(&:to_s) : []
    end

    private

    # Pages need exactly one menu and their [[links]] must resolve
    def validate_page(page)
      menus = page.references.map { |r| r[:instance] }.select { |i| i.klass == "PageMenu" }.uniq
      @errors << "#{page.path_ref}: Page '#{page.name}' is not contained in any PageMenu" if menus.empty? && !page.home?
      @errors << "#{page.path_ref}: Page '#{page.name}' is contained in several PageMenus (#{menus.map(&:name).join(", ")})" if menus.length > 1

      links = Archsight::Helpers::WikiLinks.new(@database)
      page.annotations["page/content"].to_s.gsub(Archsight::Helpers::Embeds::PATTERN, "").scan(Archsight::Helpers::WikiLinks::PATTERN).map { |match| match.first.strip }.each do |target|
        next if links.resolve(target).is_a?(String)

        @errors << "#{page.path_ref}: Page '#{page.name}' links to unknown or ambiguous [[#{target}]]"
      end

      Helpers::Macros.problems(page.annotations["page/content"].to_s, context: Helpers::Macros::Context.new(@database, page)).each do |problem|
        @errors << "#{page.path_ref}: Page '#{page.name}' has a macro #{problem}"
      end
    end

    def validate_menu(menu)
      validate_menu_cycle(menu)
      opened = menu.relations(:opens, :pages)
      @errors << "#{menu.path_ref}: PageMenu '#{menu.name}' opens several pages (#{opened.map(&:name).join(", ")}), it can open one" if opened.length > 1
      (opened & menu.relations(:contains, :pages)).each do |page|
        @errors << "#{menu.path_ref}: PageMenu '#{menu.name}' opens and also contains page '#{page.name}'"
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

    # The values of a unique annotation (aliases) must not be shared by two resources of a kind
    def validate_unique_annotations
      @database.instances.each do |klass, instances_hash|
        next unless klass.respond_to?(:annotations)

        klass.annotations.select(&:unique?).reject(&:pattern?).each do |annotation|
          owners = {}
          instances_hash.each_value { |instance| check_unique_values(annotation, instance, owners) }
        end
      end
    end

    def check_unique_values(annotation, instance, owners)
      Array(annotation.value_for(instance)).each do |value|
        owner = owners[value]
        if owner.nil?
          owners[value] = instance
        elsif !owner.equal?(instance)
          @errors << "#{instance.path_ref}: #{instance.klass} '#{instance.name}': #{annotation.key} '#{value}' " \
                     "is already used by '#{owner.name}' (#{owner.path_ref})"
        end
      end
    end

    # Declared relations must not lead back to where they started (see the "Direction of Relations" modeling guide)
    def validate_relation_cycles
      graph = relation_graph
      strongly_connected_groups(graph).each do |group|
        cycle = cycle_through(group.first, group, graph)
        names = cycle.map { |step| step[:to].name }
        start = group.first
        path = ([start.name] + names).zip(cycle.map { |step| step[:verb] }).flat_map { |name, verb| [name, verb && "-#{verb}->"] }.compact
        @errors << "#{start.path_ref}: #{start.klass} '#{start.name}' is part of a relation cycle (#{path.join(" ")})"
      end
    end

    # { instance => [{ verb:, to: }] } over the declared relations
    def relation_graph
      graph = {}
      @database.instances.each_value do |instances_hash|
        instances_hash.each_value do |instance|
          graph[instance] = instance.class.declared_relations.flat_map do |verb, key, _kind|
            next [] if CYCLE_EXEMPT_VERBS.include?(verb)

            instance.relations(verb, key).map { |target| { verb: verb, to: target } }
          end
        end
      end
      graph
    end

    # Groups of instances that reach each other (iterative Tarjan, the graph can be deep); a single instance counts
    # only when it points at itself
    def strongly_connected_groups(graph)
      index = {}
      lowlink = {}
      on_stack = {}
      stack = []
      groups = []
      counter = 0

      graph.each_key do |root|
        next if index.key?(root)

        work = [[root, 0]]
        until work.empty?
          node, edge = work.last
          if edge.zero?
            index[node] = lowlink[node] = counter
            counter += 1
            stack << node
            on_stack[node] = true
          end

          edges = graph[node] || []
          if edge < edges.length
            work.last[1] += 1
            target = edges[edge][:to]
            if !index.key?(target)
              work << [target, 0]
            elsif on_stack[target]
              lowlink[node] = [lowlink[node], index[target]].min
            end
          else
            work.pop
            lowlink[work.last.first] = [lowlink[work.last.first], lowlink[node]].min unless work.empty?
            next unless lowlink[node] == index[node]

            group = []
            loop do
              member = stack.pop
              on_stack[member] = false
              group << member
              break if member.equal?(node)
            end
            groups << group if group.length > 1 || edges.any? { |e| e[:to].equal?(node) }
          end
        end
      end
      groups
    end

    # One concrete cycle through `start` inside its group: [{ verb:, to: }, ...] ending at `start`
    def cycle_through(start, group, graph)
      members = group.to_h { |member| [member, true] }
      queue = [[start, []]]
      seen = { start => true }
      until queue.empty?
        node, path = queue.shift
        graph[node].each do |edge|
          next unless members[edge[:to]]
          return path + [edge] if edge[:to].equal?(start)
          next if seen[edge[:to]]

          seen[edge[:to]] = true
          queue << [edge[:to], path + [edge]]
        end
      end
      []
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
      validate_view_blocks(instance, key, value)
      validate_requirements_blocks(instance, key, value)
      validate_asset_images(instance, key, value)
      validate_embeds(instance, key, value)
    end

    # ![[View/Name]] and ![[Analysis/Name]] must name an existing view or analysis
    def validate_embeds(instance, key, value)
      Helpers::Embeds.new(@database).audit(value).each do |problem|
        reason = Helpers::Embeds::REASONS.fetch(problem[:problem])
        @errors << "#{instance.path_ref}: #{instance.klass} '#{instance.name}' embeds ![[#{problem[:reference]}]] in annotation '#{key}': #{reason}"
      end
    end

    # Every relative image must resolve to an asset that is served (see Archsight::Assets)
    def validate_asset_images(instance, key, value)
      resources_dir = @database.path if @database.respond_to?(:path)
      base = resources_dir && Archsight::Assets.base_dir_for(instance, resources_dir: resources_dir)
      return unless base

      Helpers::AssetImages.audit(value, base_dir: base, resources_dir: resources_dir).each do |problem|
        @errors << "#{instance.path_ref}: #{instance.klass} '#{instance.name}' #{asset_problem(problem)} in annotation '#{key}'"
      end
      validate_asd_assets(instance, key, value, base, resources_dir)
    end

    # An embedded .asd file must render like an ```asd block does
    def validate_asd_assets(instance, key, value, base, resources_dir)
      Helpers::AssetImages.asd_files(value, base_dir: base, resources_dir: resources_dir).each do |path, file|
        render_diagram_source(instance, "#{path} (annotation '#{key}')", File.read(file, encoding: "UTF-8"))
      end
    end

    def asset_problem(problem)
      ref = problem[:reference].inspect
      case problem[:status]
      when :outside then "references asset #{ref} outside the resources directory"
      when :type then "references #{ref}, a file type that is not served (#{Archsight::Assets::TYPES.keys.join(" ")})"
      else "references asset #{ref} that does not exist (#{problem[:path]})"
      end
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

    # Every ```view block must be a valid View, or the page shows an error box instead of the view
    def validate_view_blocks(instance, key, value)
      Helpers::ViewBlocks.sources(value).each_with_index do |source, index|
        spec = Helpers::ViewBlocks.parse(source)
        check_view_components(instance, spec[:fields])
      rescue Helpers::ViewBlocks::Error => e
        @errors << "#{instance.path_ref}: View error in annotation '#{key}' (view block #{index + 1}): #{e.message}"
      end
    end

    # Every ```requirements block must be a valid filter, or the page shows an error box instead of the table
    def validate_requirements_blocks(instance, key, value)
      Helpers::RequirementsBlocks.sources(value).each_with_index do |source, index|
        Helpers::RequirementsBlocks.parse(source)
      rescue Helpers::RequirementsBlocks::Error => e
        @errors << "#{instance.path_ref}: Requirements error in annotation '#{key}' (requirements block #{index + 1}): #{e.message}"
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
      check_view_components(instance, instance.annotations["view/fields"].to_s.split(",").map(&:strip))
    end

    def check_view_components(instance, fields)
      fields.each do |field|
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
