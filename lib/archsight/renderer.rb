# frozen_string_literal: true

module Archsight
  # GraphvisRenderer renders instances of the database
  module GraphvisRenderer
    FONT = "Helvetica"

    def gname(inst)
      "#{inst.class}/#{inst.name}"
    end

    def css_class(inst)
      base_class = inst.class.name.to_s.gsub("::", "")
      layer_class = "layer-#{inst.class.layer}"
      "#{base_class} #{layer_class}"
    end

    def has_relations?(inst, klass)
      # Check outgoing relations defined on this class
      klass.relations.each do |verb, kind|
        return true if inst.relations(verb, kind).any?
      end
      false
    end

    # Check if any resource in the database references this instance
    def has_incoming_relations?(db, inst)
      db.instances.each do |other_klass, instances|
        other_klass.relations.each do |_verb, target_kind|
          next unless target_kind == inst.class

          instances.each_value do |other_inst|
            return true if other_inst.relations(_verb, target_kind).include?(inst)
          end
        end
      end
      false
    end

    def gnode(graph, inst, opts = {})
      label = "<TABLE><TR><TD><B>#{inst.name}</B></TD></TR><TR><TD>#{inst.klass}</TD></TR></TABLE>"
      label = inst.name if opts[:simple_label]
      attrs = { class: css_class(inst), shape: :box, style: "rounded,filled", fontname: FONT, label: label,
                href: "/kinds/#{inst.klass}/instances/#{inst.name}" }
      # A resource at the depth limit with more dependencies: dashed, its own page shows them
      attrs.merge!(style: "rounded,filled,dashed", tooltip: "More dependencies: open it to explore them") if opts[:truncated]
      graph.node gname(inst), attrs
    end

    def gedge(graph, a_inst, b_inst, label)
      graph.edge gname(a_inst), gname(b_inst), label: label, fontname: "#{FONT} italic"
    end

    def create_graph_all(db, root_kinds: nil, max_depth: 3, allowed_kinds: nil)
      root_kinds ||= [Archsight::Resources["BusinessProduct"], Archsight::Resources["BusinessProcess"]]

      # Default allowed kinds for overview: Products, Processes, Services, and Teams
      allowed_kinds ||= [
        Archsight::Resources["BusinessProduct"],
        Archsight::Resources["BusinessProcess"],
        Archsight::Resources["ApplicationService"],
        Archsight::Resources["BusinessActor"]
      ]
      allowed_kinds_set = allowed_kinds.to_set

      Archsight::Graphvis.new("all").draw_dot do |g|
        nodes = {} # Track visited nodes
        edges = {} # Track created edges

        # Collect root instances
        queue = [] # [instance, depth] pairs
        root_kinds.each do |klass|
          db.instances[klass]&.each_value do |inst|
            next if inst.abandoned?

            queue << [inst, 0]
          end
        end

        # BFS traversal with depth limit
        while queue.any?
          inst, depth = queue.shift
          next if nodes[inst]

          nodes[inst] = true
          gnode(g, inst, simple_label: true)

          # Stop following relations at max depth
          next if depth >= max_depth

          inst.class.relations.each do |verb, kind|
            inst.relations(verb, kind).each do |rel|
              next if rel.abandoned?
              next unless allowed_kinds_set.include?(rel.class)

              edge_key = "#{gname(inst)}|#{verb}|#{gname(rel)}"
              unless edges[edge_key]
                gedge(g, inst, rel, verb)
                edges[edge_key] = true
              end

              queue << [rel, depth + 1] unless nodes[rel]
            end
          end
        end
      end
    end

    # The layers the `structure` scope of an instance graph follows: the application and technology stack, without
    # organisation (actors, roles), motivation, compliance, implementation and other resources
    STRUCTURE_LAYERS = %w[application technology].freeze

    # The dependency graph of one instance: the resources its relations lead to, breadth first, so a resource gets
    # the depth of its shortest path.
    # @param max_depth [Integer, nil] follow relations this many steps from the instance (nil: all the way). A
    #   resource at the limit that has more relations is drawn dashed.
    # @param scope [Symbol] :all follows every relation, :structure only those to application and technology resources
    def create_graph_one(db, klass_pat, name_pat, max_depth: nil, scope: :all)
      klass = Archsight::Resources[klass_pat] || raise("kind #{klass_pat} unknown")
      root = db.instances[klass]&.[](name_pat) || raise("name #{name_pat} for kind #{klass_pat} not found")

      Archsight::Graphvis.new("#{klass_pat}:#{name_pat}").draw_dot do |g|
        nodes = {}
        edges = {}
        queue = [[root, 0]]
        while queue.any?
          inst, depth = queue.shift
          next if nodes[inst]

          nodes[inst] = true
          targets = graph_targets(inst, scope)
          if max_depth && depth >= max_depth
            gnode(g, inst, truncated: targets.any?)
            next
          end

          gnode(g, inst)
          targets.each do |verb, rel|
            edge_name = "#{gname(inst)}|#{verb}|#{gname(rel)}"
            gedge(g, inst, rel, verb) unless edges[edge_name]
            edges[edge_name] = true
            queue << [rel, depth + 1] unless nodes[rel]
          end
        end
      end
    end

    # The [verb, target] pairs of an instance's relations the graph follows in the scope
    def graph_targets(inst, scope)
      inst.class.relations.flat_map do |verb, kind|
        inst.relations(verb, kind).filter_map do |rel|
          [verb, rel] if scope != :structure || STRUCTURE_LAYERS.include?(rel.class.layer)
        end
      end
    end
  end
end
