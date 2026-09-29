# frozen_string_literal: true

require_relative "../test_helper"

class DiagramDataflowRoutingTest < Minitest::Test
  # `dataflow_backtracks?`/`dataflow_loop_into_box` are private -- exercised
  # directly via `send`, the same way spec/renderer_spec.rb reaches into
  # `EdgeRouting`'s own internals for its own routing-refinement tests. They
  # read no instance state, so a bare `allocate`d instance (skipping
  # `initialize`, which otherwise wants a real graph/box set) is enough to
  # call them.

  # #dataflow_backtracks? (private)

  def test_dataflow_backtracks_is_false_when_the_route_continues_past_the_box_on_a_new_side
    # The ordinary "L-shaped path" case: entering on the left edge and
    # continuing on toward a point on the far side.
    assert_same false, routing.send(:dataflow_backtracks?, box, :left, [400, 200])
  end

  def test_dataflow_backtracks_is_true_when_the_route_immediately_doubles_back_past_the_same_side_it_entered
    # Regression test for examples/paas_nas_operator.asd's mount_nfs
    # dataflow: the route entering frontend_nics1 (from vip) and the
    # route leaving it (toward nfs1) both touched its left edge, with
    # departure continuing on further left still (nfs1 sits further
    # left again).
    assert_same true, routing.send(:dataflow_backtracks?, box, :left, [230, 200])
  end

  # #dataflow_loop_into_box (private)

  def test_dataflow_loop_into_box_returns_two_distinct_points_both_pushed_into_the_interior_straddling_the_boundary_point
    # Pushing one shared point into the interior in the backtracking
    # case above would force the line to double back across ground it
    # just covered -- a single point can only read as a sharp reversal
    # spike, never a loop. Two points close together, each nudged in
    # only a little, give the spline an actual small loop to draw.
    entry, exit_ = routing.send(:dataflow_loop_into_box, box, [250, 100], :left)

    refute_equal exit_, entry
    assert_operator entry[0], :>, 250 # pushed into the interior
    assert_operator exit_[0], :>, 250
    assert_operator entry[0], :<, box.right # modest, not a deep push
    assert_operator (entry[1] - exit_[1]).abs, :>, 0 # separated along the touched side
  end

  private

  def routing = @routing ||= Archsight::Diagram::DataflowRouting.allocate
  # left=250 right=350 top=70 bottom=130
  def box = @box ||= Archsight::Diagram::Layout::Box.new(300, 100, 100, 60)
end
