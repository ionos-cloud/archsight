# frozen_string_literal: true

module Archsight
  module Diagram
    class Error < StandardError; end
    class ParseError < Error; end
    class GraphError < Error; end
  end
end
