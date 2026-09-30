# frozen_string_literal: true

module Archsight
  module Diagram
    class DataflowRouting
      # When two or more branches of a `hop group` already agree on the
      # same label (the common case -- most branches in a group mean the
      # same thing as each other), showing it once on the shared trunk (or,
      # lacking a trunk, on just the first agreeing branch) reads as one
      # flow with one label; showing it on every one of them too would just
      # repeat it. This is a *majority*, not unanimity -- a branch with its
      # own genuinely different label (e.g. "read messages to update
      # assignments" alongside four branches all just saying "Events")
      # always keeps it; only the branches actually sharing the majority
      # label get deduplicated.
      class BranchLabelPolicy
        attr_reader :shared_label

        def initialize(group, has_trunk:)
          @group = group
          @has_trunk = has_trunk
          @shared_label = compute_shared_label
          @first_shared_index = has_trunk ? nil : group.branches.index { |b| b.label == @shared_label }
        end

        # `branch`'s own attrs, with its `label` stripped if it's one of
        # the branches sharing `shared_label` and that label is hosted
        # elsewhere instead (the trunk, or -- lacking a trunk -- the first
        # agreeing branch).
        def attrs_for(branch, index)
          return branch.attrs unless @shared_label && branch.label == @shared_label

          hosted_elsewhere = @has_trunk || index != @first_shared_index
          hosted_elsewhere ? branch.attrs.except("label") : branch.attrs
        end

        private

        def compute_shared_label
          label_tally = @group.branches.map(&:label).tally
          shared_label, shared_count = label_tally.max_by { |_, count| count }
          shared_count && shared_count > 1 ? shared_label : nil
        end
      end
    end
  end
end
