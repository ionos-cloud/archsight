# frozen_string_literal: true

require_relative "../test_helper"

class DiagramIncludesTest < Minitest::Test
  FILES = {
    "db" => %(component "db" { label "DB" }\n),
    "cache" => %(component "cache" { label "Cache" }\napp_edge -> cache\n),
    "nested" => %(include "db"\ncomponent "n" { }\n),
    "loop-a" => %(include "loop-b"\n),
    "loop-b" => %(include "loop-a"\n),
    "flow" => %(component "x" { }\ncomponent "y" { }\ntheme "compact"\ndataflow "f" { hop "x"; hop "y" }\n),
    "bad" => "not valid ((\n",
    "stack" => %(stack { component "s1" { } component "s2" { } }\n),
    "missing-one" => :missing, "denied" => :forbidden, "weird" => :invalid
  }.freeze
  LOADER = ->(path) { FILES.fetch(path) }

  def expand(source, loader: LOADER) = Archsight::Diagram.expand(source, includes: loader)

  def ids(statements)
    statements.flat_map { |s| s.is_a?(Archsight::Diagram::AST::Block) ? [s.id, *ids(s.children)] : [] }
  end

  def test_an_include_is_replaced_by_the_included_statements_at_its_position
    result = expand(%(component "a" { }\ninclude "db"\ncomponent "z" { }\n))

    assert_equal %w[a db z], ids(result.statements)
    assert_equal({ "db" => FILES["db"] }, result.sources)
  end

  def test_an_include_inside_a_container_lands_in_that_container
    result = expand(%(group "g" { component "a" { } include "db" }\n))
    group = result.statements.first

    assert_equal %w[a db], group.children.map(&:id)
  end

  def test_includes_nest
    assert_equal %w[db n], ids(expand(%(include "nested"\n)).statements)
  end

  def test_anonymous_layers_of_included_sources_do_not_collide
    result = expand(%(stack { component "m" { } }\ninclude "stack"\ninclude "stack2"\n), loader: ->(p) { p == "stack2" ? FILES["stack"].sub("s1", "t1").sub("s2", "t2") : FILES[p] })

    all = ids(result.statements)

    assert_equal all.uniq, all
    assert_equal 8, all.length # three stacks, five components
    assert_includes Archsight::Diagram.render(%(stack { component "m" { } }\ninclude "stack"\n), includes: LOADER), "asd-node-s1"
  end

  def test_an_included_edge_may_name_nodes_of_the_including_diagram
    svg = Archsight::Diagram.render(%(component "app_edge" { }\ninclude "cache"\n), includes: LOADER)

    assert_includes svg, "asd-node-cache"
  end

  def test_an_include_cycle_is_an_error
    error = assert_raises(Archsight::Diagram::IncludeError) { expand(%(include "loop-a"\n)) }

    assert_includes error.message, "include cycle: loop-a -> loop-b -> loop-a"
  end

  def test_nesting_depth_is_limited
    loader = ->(path) { %(include "#{path}x"\n) }
    error = assert_raises(Archsight::Diagram::IncludeError) { expand(%(include "a"\n), loader: loader) }

    assert_includes error.message, "deeper than"
  end

  def test_the_number_of_includes_is_limited
    source = (%(include "db"\n) * 101)
    error = assert_raises(Archsight::Diagram::IncludeError) { expand(source) }

    assert_includes error.message, "too many includes"
  end

  def test_dataflows_and_settings_are_ignored_inside_a_container_with_a_warning
    result = expand(%(group "g" { include "flow" }\n))

    assert_equal %w[g x y], ids(result.statements)
    assert_equal 2, result.warnings.length
    assert_includes result.warnings.first, "theme setting"
    assert_includes result.warnings.last, %(dataflow "f")
    refute(result.statements.flat_map { |s| s.respond_to?(:children) ? s.children : [s] }.any?(Archsight::Diagram::AST::DataFlow))
  end

  def test_dataflows_and_settings_are_kept_at_the_top_level
    result = expand(%(include "flow"\n))

    assert_empty result.warnings
    assert(result.statements.any?(Archsight::Diagram::AST::DataFlow))
    assert(result.statements.any?(Archsight::Diagram::AST::Setting))
  end

  def test_render_collects_the_warnings
    warnings = []
    Archsight::Diagram.render(%(group "g" { include "flow" }\n), includes: LOADER, warnings: warnings)

    assert_equal 2, warnings.length
  end

  def test_loader_failures_are_reported_with_the_path_and_line
    { "missing-one" => "not found", "denied" => "is not allowed", "weird" => "is not a valid include path" }.each do |path, reason|
      error = assert_raises(Archsight::Diagram::IncludeError) { expand(%(\ninclude "#{path}"\n)) }

      assert_includes error.message, %(include "#{path}" #{reason} (line 2))
    end
  end

  def test_a_parse_error_in_an_included_source_names_the_include
    error = assert_raises(Archsight::Diagram::IncludeError) { expand(%(include "bad"\n)) }

    assert_includes error.message, %(in include "bad":)
  end

  def test_without_a_loader_includes_are_not_available
    error = assert_raises(Archsight::Diagram::IncludeError) { expand(%(include "db"\n), loader: nil) }

    assert_includes error.message, "not available here"
  end

  def test_a_source_without_includes_needs_no_loader
    assert_equal %w[a], ids(expand(%(component "a" { }\n), loader: nil).statements)
  end

  def test_resource_references_follow_includes
    loader = ->(_) { %(component "r" { resource "Some:Thing" }\n) }

    assert_equal ["Some:Thing"], Archsight::Diagram.resource_references(%(include "x"\n), includes: loader)
  end
end
