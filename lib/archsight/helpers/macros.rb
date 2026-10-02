# frozen_string_literal: true

require "cgi"

module Archsight
  module Helpers
    # Inline macros in markdown, named like the macros of Confluence: `{name:arguments}`, for example
    # `{status:yellow WIP}` or `{emoticon:2705}`.
    #
    # A macro is registered under its name with a handler (duck-typed):
    # - `parse(arguments)` -> a value, or nil when the arguments are not valid
    # - `html(value, context)` -> the HTML shown in the web UI (nil keeps the text; `context` is a Context, nil outside
    #   a page)
    # - `confluence(value, context)` -> the Confluence storage format for the export (nil keeps the text)
    # - `problem(arguments, context)` -> a message for the linter, nil if the arguments are fine
    #
    # Text that is not a registered macro, or whose arguments are rejected, stays exactly as written, so braces in
    # prose or JSON are safe. Code is never touched. Arguments never contain `|` (kramdown reads a paragraph line
    # with `|` as a table row), `{`, `}` or a line break.
    module Macros
      PATTERN = /\{([a-z][a-z0-9-]*)(?::([^{}|\n]*))?\}/
      Context = Struct.new(:database, :page)
      HTML_CODE = %r{(<pre\b.*?</pre>|<code\b.*?</code>)}m
      MARKDOWN_CODE = /(^[ \t]*(?:```|~~~).*?^[ \t]*(?:```|~~~)[ \t]*$|`[^`\n]*`)/m

      @handlers = {}

      class << self
        # @param name [String] the macro name as written in `{name:...}`
        def register(name, handler)
          @handlers[name.to_s] = handler
        end

        def handler(name) = @handlers[name.to_s]

        # The macros of rendered HTML (outside code) replaced by their HTML. A handler can need the page it is on
        # (`context`, a Context); one that cannot answer without it (`html` returns nil) leaves the text as written.
        # A block macro (`block?`) that is alone in its paragraph replaces the whole paragraph.
        def render(html, context: nil)
          rendered = replace_in(html, HTML_CODE, unescape: true) { |macro, value| macro.html(value, context) }
          rendered.gsub(%r{<p>(<(?:ul|div) class="[^"]*\bmacro-block\b.*?</(?:ul|div)>)</p>}m) { Regexp.last_match(1) }
        end

        # The macros of markdown (outside code spans and fences), each replaced by what the block returns for the
        # handler and the parsed value; a block result of nil leaves the text as written.
        def replace(markdown, &)
          replace_in(markdown, MARKDOWN_CODE, &)
        end

        # Problems of the registered macros in a markdown text, for the linter
        # @return [Array<String>]
        def problems(markdown, context: nil)
          found = []
          scan(markdown) do |name, arguments, macro|
            message = macro.problem(arguments, context)
            found << "{#{name}:#{arguments}}: #{message}" if message
          end
          found
        end

        private

        def replace_in(text, code, unescape: false, &)
          text.split(code).each_with_index.map { |part, i| i.odd? ? part : expand(part, unescape, &) }.join
        end

        # In rendered HTML the arguments are escaped text (`&amp;`), the handlers want the text as written
        def expand(text, unescape)
          text.gsub(PATTERN) do |source|
            macro = handler(Regexp.last_match(1))
            arguments = Regexp.last_match(2).to_s
            value = macro&.parse(unescape ? CGI.unescapeHTML(arguments) : arguments)
            value.nil? ? source : (yield(macro, value) || source)
          end
        end

        def scan(markdown)
          markdown.split(MARKDOWN_CODE).each_with_index do |part, i|
            next if i.odd?

            part.scan(PATTERN) do |name, arguments|
              macro = handler(name)
              yield name, arguments.to_s, macro if macro
            end
          end
        end
      end
    end
  end
end

require_relative "macros/status"
require_relative "macros/emoticon"
require_relative "macros/jira"
require_relative "macros/children"
