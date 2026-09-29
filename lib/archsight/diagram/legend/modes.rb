# frozen_string_literal: true

module Archsight
  module Diagram
    module Legend
      # Where the legend goes, relative to the diagram (`legend "<mode>"` in
      # the source, `--legend` on the command line): `auto` picks `right`
      # for a diagram taller than it is wide and `bottom` otherwise; `none`
      # leaves it out. Kept apart from the rest of `Legend` so `Graph` can
      # validate the setting without depending on the legend's layout.
      MODES = %w[auto bottom right left top none].freeze
      DEFAULT_MODE = "auto"
    end
  end
end
