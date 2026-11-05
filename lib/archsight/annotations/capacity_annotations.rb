# frozen_string_literal: true

# Capacity module adds the counts that describe how much a group of hosts holds in reserve. A reserve is a number,
# not a machine: any host can take the role and the actual spare changes over time, so it is not a flag on a device.
module Archsight::Annotations::Capacity
  def self.included(base)
    base.class_eval do
      annotation "capacity/spareHosts",
                 description: "Number of hosts held in reserve (n+1 spares), not tied to a specific machine; the source is a link/* annotation",
                 title: "Spare Hosts",
                 type: Integer,
                 validator: ->(value) { "'#{value}' is not a count of zero or more" unless value.match?(/\A\d+\z/) }
    end
  end
end
