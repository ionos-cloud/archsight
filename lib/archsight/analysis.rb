# frozen_string_literal: true

module Archsight
  # Analysis module provides sandboxed execution of Analysis scripts
  module Analysis
  end
end

require_relative "analysis/result"
require_relative "analysis/sandbox"
require_relative "analysis/executor"
