# frozen_string_literal: true

module Archsight; end
module Archsight::Web; end
module Archsight::Web::API; end

# Parameters and JSON of `GET /api/v1/requirements` (see Archsight::Requirements)
module Archsight::Web::API::RequirementsHelpers
  # @param name [Symbol] a comma separated list parameter, every value of which must be one of `allowed`
  def csv_param(name, allowed)
    values = params[name].to_s.split(",").map(&:strip).reject(&:empty?)
    invalid = values - allowed
    json_error("Parameter '#{name}' must be #{allowed.join(", ")}, not '#{invalid.first}'", status: 400, error_type: "BadRequest") unless invalid.empty?

    values
  end

  def build_requirements_response(query, requirements, query_time_ms)
    {
      query: query,
      total: requirements.length,
      query_time_ms: query_time_ms,
      requirements: requirements.map { |r| r.merge(story: r[:story] && markdown(r[:story])) }
    }
  end
end
