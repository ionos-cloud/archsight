# frozen_string_literal: true

module Archsight
  module Summary
    # What a summary follows from a resource, depending on its layer: an ordered list of sections, each one a set of
    # relation verbs in one direction (and how many steps deep).
    #
    # One section per line, `<out|in> <verb>[, <verb>...] [depth=N][: <title>]`:
    #
    #     in servedBy, realizedBy: Used by
    #     out dependsOn depth=2: Depends on
    #     in *: Referenced by
    #
    # `out` = the resource points at the target (it declares the relation), `in` = the target points at it; `*` = every
    # verb. The built-in lenses below apply when the model has no Config of type `summary`; its annotation
    # `summary/lens-<layer>` replaces the lens of that layer and `summary/lens-<Kind>` the one of a single kind (the
    # kind wins), so lenses are tuned without a release.
    module Lens
      TYPE = "summary" # the `config/type` of the Config that holds the lenses
      DEFAULT_CONFIG = "default"
      MAX_DEPTH = 5

      Section = Struct.new(:title, :direction, :verbs, :depth) do
        def all_verbs?
          verbs == ["*"]
        end
      end

      class ParseError < StandardError; end

      DEFAULTS = {
        "motivation" => <<~LENS,
          in hasConcern: Stakeholders
          out representedBy: Represented by
          in refinedBy: Refines
          out refinedBy: Refined by
          in realizes, partiallyRealizes, plans: Realized by
          in satisfies, stipulates: Satisfied by
          out mitigatedBy: Mitigated by
          in assesses, influences: Assessed and influenced by
          out evidencedBy: Evidence
          out ownedBy: Owners
          in mentions, depicts: Documented in
        LENS
        "strategy" => <<~LENS,
          out realizes: Realizes
          out servedBy: Served by
          in hasConcern: Stakeholders
          in realizes: Realized by
          in mentions, depicts: Documented in
        LENS
        "implementation" => <<~LENS,
          out contains: Contains
          in contains: Part of
          out compares: Compares
          out closedBy: Closed by
          in closedBy: Closes
          out affects: Affects
          out realizes: Realizes
          in realizes: Realized by
          out performedBy, ownedBy: People
          in mentions, depicts: Documented in
        LENS
        "business" => <<~LENS,
          out performedBy, ownedBy, executedBy, agreedBy: People
          out guidedBy: Controls
          out servedBy: Supported by
          out exposes: Exposes
          out aggregates, composedOf: Composed of
          in aggregates, composedOf, compositeOf: Part of
          out realizes, satisfies, stipulates: Requirements
          out covers: Covers
          out evidencedBy, provides: Evidence
          in performedBy, ownedBy, executedBy: Responsible for
          in maintainedBy, operatedBy, contributedBy: Maintains and operates
          in mentions, depicts: Documented in
        LENS
        "application" => <<~LENS,
          out exposes: Interfaces
          out realizedThrough, realizedBy: Realized through
          in realizedThrough, realizedBy: Realizes
          out servedBy, provisions: Runs on
          out dependsOn: Depends on
          in dependsOn: Used by
          in serves: Serves
          out maintainedBy, operatedBy: Owners
          out realizes, partiallyRealizes, plans: Requirements
          out evidencedBy: Evidence
          in servedBy: Served
          in exposes: Exposed by
          in mentions, depicts: Documented in
        LENS
        "technology" => <<~LENS,
          out servedBy, realizedBy, suppliedBy, realizedThrough: Built on
          in servedBy, realizedBy, suppliedBy, assignedTo: Runs on it
          out composedOf, aggregates: Composed of
          in composedOf, aggregates: Part of
          out locatedAt: Located at
          out connectedTo, connects: Connected to
          out maintainedBy, operatedBy, ownedBy, contributedBy: Owners
          out realizes, partiallyRealizes, plans: Requirements
          out evidencedBy: Evidence
          in mentions, depicts: Documented in
        LENS
        "other" => <<~LENS
          out *: Points at
          in *: Referenced by
          in mentions, depicts: Documented in
        LENS
      }.freeze

      # Kinds whose layer lens is too coarse; looked up before the lens of the layer
      KIND_DEFAULTS = {
        "BusinessActor" => <<~LENS,
          in performedBy, executedBy: Performs
          in ownedBy: Owns
          in maintainedBy, operatedBy, contributedBy: Maintains and operates
          out compositeOf: Composed of
          in compositeOf: Part of
          in representedBy: Represented as stakeholder
          in agreedBy: Contracts
          in servedBy: Serves
          in mentions, depicts: Documented in
        LENS
        "ApplicationService" => <<~LENS,
          out realizedThrough: Realized through
          out dependsOn: Depends on
          in dependsOn: Used by
          in servedBy: Serves
          out maintainedBy: Owners
          out realizes, partiallyRealizes, plans: Requirements
          out evidencedBy: Evidence
          in mentions, depicts: Documented in
        LENS
        "MotivationAssessment" => <<~LENS
          out assesses: Assesses
          out influences: Influences
          out mitigatedBy: Mitigated by
          out ownedBy: Owners
          in mentions, depicts: Documented in
        LENS
      }.freeze

      class << self
        # The sections for a resource of `kind` in `layer`, from the first of: the `summary/lens-<Kind>` and then the
        # `summary/lens-<layer>` of the Config named `default` of type summary (or the first of that type), the built-in
        # lens of the kind, the built-in lens of the layer
        def for(database, layer, kind: nil)
          candidates = [configured(database, kind), configured(database, layer), KIND_DEFAULTS[kind], DEFAULTS[layer]]
          candidates.compact.each do |text|
            return parse(text)
          rescue ParseError
            next # a bad Config (the linter reports it) must not break the summary: the next candidate is used
          end
          parse(DEFAULTS["other"])
        end

        # nil when `suffix` of a `summary/lens-<suffix>` key is a layer or a kind, else the message
        def key_error(suffix)
          return nil if Archsight::Resources::LAYERS.include?(suffix) || Archsight::Resources[suffix]

          "expected a layer (#{Archsight::Resources::LAYERS.join(", ")}) or a kind, not #{suffix}"
        end

        # Sections of lens text; raises ParseError naming the line
        def parse(text)
          text.to_s.lines.map.with_index(1) { |line, number| [line.strip, number] }.reject { |line, _| line.empty? || line.start_with?("#") }.map do |line, number|
            parse_line(line)
          rescue ParseError => e
            raise ParseError, "line #{number} (#{line}): #{e.message}"
          end
        end

        # nil when the text is a valid lens, else the message (the validator of the Config annotation)
        def parse_error(text)
          sections = parse(text)
          sections.empty? ? "expected at least one line like `in servedBy: Used by`" : nil
        rescue ParseError => e
          e.message
        end

        def known_verbs
          @known_verbs ||= Archsight::Resources.constants.filter_map do |name|
            klass = Archsight::Resources.const_get(name)
            klass.relations.map { |verb, _, _| verb.to_s } if klass.is_a?(Class) && klass < Archsight::Resources::Base
          end.flatten.uniq.sort
        end

        private

        def configured(database, key)
          return nil unless key

          configs = database.instances_by_kind("Config").values.select { |c| c.annotations["config/type"].to_s.casecmp?(TYPE) }
          config = configs.find { |c| c.name == DEFAULT_CONFIG } || configs.first
          text = config&.annotations&.[]("summary/lens-#{key}").to_s
          text.strip.empty? ? nil : text
        end

        def parse_line(line)
          spec, title = line.split(":", 2).map(&:strip)
          direction, rest = spec.split(/\s+/, 2)
          raise ParseError, "expected `out` or `in` first" unless %w[out in].include?(direction)

          depth = 1
          words = rest.to_s.split(/[,\s]+/).reject(&:empty?).reject do |word|
            next false unless (m = word.match(/\Adepth=(\d+)\z/))

            depth = m[1].to_i
            true
          end
          raise ParseError, "expected at least one verb" if words.empty?
          raise ParseError, "depth must be 1 to #{MAX_DEPTH}" unless depth.between?(1, MAX_DEPTH)

          verbs = words.include?("*") ? ["*"] : words
          unknown = verbs - ["*"] - known_verbs
          raise ParseError, "unknown verb #{unknown.join(", ")}" unless unknown.empty?

          Section.new(title.to_s.empty? ? "#{direction} #{verbs.join(", ")}" : title, direction, verbs, depth)
        end
      end
    end
  end
end
