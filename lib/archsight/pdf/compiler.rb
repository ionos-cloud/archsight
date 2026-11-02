# frozen_string_literal: true

require "open3"
require "timeout"
require_relative "../user_config"

module Archsight
  module Pdf
    # Raised when a document cannot be turned into a PDF; the message is safe to show
    class Error < StandardError; end

    # Raised when typst is not installed
    class Unavailable < Error; end

    # Runs the `typst` command line tool on a prepared directory. The binary is `pdf.typst` of the user
    # configuration (`ARCHSIGHT_PDF_TYPST`), else `typst` from the PATH.
    class Compiler
      DEFAULT_TIMEOUT = 60
      ERROR_LINES = 12

      def initialize(binary: nil, timeout: nil)
        @binary = binary || UserConfig.setting("pdf", "typst") || "typst"
        @timeout = (timeout || UserConfig.setting("pdf", "timeout") || DEFAULT_TIMEOUT).to_i
      end

      # @param dir [String] directory with main.typ; it is the Typst root, nothing outside of it can be read
      # @param font_paths [Array<String>] directories with additional fonts
      # @return [String] the PDF
      # @raise [Unavailable] without typst
      # @raise [Error] if typst fails or runs too long
      def compile(dir, font_paths: [])
        output = File.join(dir, "out.pdf")
        args = [@binary, "compile", "--root", dir, *font_paths.flat_map { |p| ["--font-path", p] }, File.join(dir, "main.typ"), output]
        _out, err, status = run(args, dir)
        raise Error, "typst failed:\n#{err.lines.first(ERROR_LINES).join}" unless status.success? && File.file?(output)

        File.binread(output)
      end

      # Whether PDF files can be placed as images (typst 0.14 and newer)
      def pdf_images?
        return @pdf_images if defined?(@pdf_images)

        out, status = Open3.capture2(@binary, "--version")
        version = out[/(\d+)\.(\d+)/]
        @pdf_images = status.success? && !version.nil? && (Gem::Version.new(version) >= Gem::Version.new("0.14"))
      rescue Errno::ENOENT
        raise Unavailable, "typst is not installed (set ARCHSIGHT_PDF_TYPST to its path)"
      end

      private

      def run(args, dir)
        Open3.popen3(*args, chdir: dir) do |stdin, stdout, stderr, thread|
          stdin.close
          out = Thread.new { stdout.read }
          err = Thread.new { stderr.read }
          unless thread.join(@timeout)
            Process.kill("KILL", thread.pid)
            raise Error, "typst took longer than #{@timeout} seconds"
          end
          [out.value, err.value, thread.value]
        end
      rescue Errno::ENOENT
        raise Unavailable, "typst is not installed (set ARCHSIGHT_PDF_TYPST to its path)"
      end
    end
  end
end
