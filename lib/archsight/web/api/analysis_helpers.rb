# frozen_string_literal: true

module Archsight; end
module Archsight::Web; end
module Archsight::Web::API; end

# JSON of `POST /api/v1/kinds/Analysis/instances/:name/execute`: the result and its sections
module Archsight::Web::API::AnalysisHelpers
  def build_analysis_result(result)
    data = {
      name: result.name,
      success: result.success?,
      has_findings: result.has_findings?,
      duration: result.duration,
      sections: result.sections.map { |s| serialize_analysis_section(s) }
    }

    if result.failed?
      data[:error] = result.error
      data[:error_backtrace] = result.error_backtrace if result.error_backtrace&.any?
    end

    data
  end

  def serialize_analysis_section(section)
    case section[:type]
    when :heading
      { type: "heading", level: section[:level], text: section[:text] }
    when :text
      { type: "text", content: markdown(section[:content]) }
    # the *_html fields: the values as inline markdown with [[Kind/Name]] links, next to the raw values
    when :message
      { type: "message", level: section[:level].to_s, message: section[:message],
        message_html: analysis_html(section[:message]) }
    when :table
      { type: "table", headers: section[:headers], rows: section[:rows],
        rows_html: section[:rows].map { |row| row.map { |cell| analysis_html(cell) } } }
    when :list
      { type: "list", items: section[:items], items_html: section[:items].map { |item| analysis_html(item) } }
    when :code
      { type: "code", lang: section[:lang], content: section[:content] }
    else
      { type: section[:type].to_s }
    end
  end

  # A value of a table cell, list item or message as html: HTML in it stays text (escaped first) except a line
  # break (`<br>` or a newline, the usual way to break a line in a table cell), markdown and [[Kind/Name]] links are
  # rendered; a value without markup is only escaped, so large tables stay cheap
  def analysis_html(value)
    escaped = Rack::Utils.escape_html(value.to_s).gsub(%r{&lt;br\s*/?&gt;}i, "<br>").gsub(/\r?\n/, "<br>")
    escaped.match?(/[*_`\[{]|https?:/) ? inline_markdown(escaped) : escaped
  end
end
