# frozen_string_literal: true

require "open3"
require "shellwords"
require "tmpdir"
require "yaml"
require_relative "../handler"
require_relative "../registry"

# Command handler - runs a program of the resources repository as an import, in any language. The program writes its
# resources itself (usually to ARCHSIGHT_OUTPUT_PATH); archsight adds the self marker, so caching, `import/dependsOn`,
# `-f` and `-n` work as for any other import.
#
# The program runs in the root of the repository that holds the resources directory (the resources directory when it
# is not in a git repository), with a clean environment: PATH, HOME, LANG and the variables below, plus the variables
# listed in `import/config/env` (credentials, for example).
#
#   ARCHSIGHT_RESOURCES_DIR - the resources directory
#   ARCHSIGHT_CACHE_DIR     - where the git-based imports clone repositories
#   ARCHSIGHT_IMPORT_NAME   - the name of the Import
#   ARCHSIGHT_OUTPUT_PATH   - a file for the YAML resources the program generates; archsight writes them unchanged to
#                             import/outputPath (generated/<name>.yaml without one), followed by the import's marker
#
# The output file belongs to the import: it is replaced on every run and removed when outputPath changes. Documents
# are not marked as generated; a program that wants that sets `generated/script: <import name>` itself (only on kinds
# that have the `generated` annotations), while documents that add relations to hand-written resources stay unmarked.
#
# Configuration:
#   import/config/command - the command line (split like a shell does, but run without one; use `sh -c '...'` for
#                           pipes); a relative program path is relative to the working directory
#   import/config/env     - names of further environment variables to pass, comma separated
#   import/config/outputs - files the program writes besides the output path, glob patterns relative to the
#                           resources directory, comma separated; recorded like Handler#write_file
#   import/config/workdir - working directory relative to the resources directory (default: the repository root)
class Archsight::Import::Handlers::Command < Archsight::Import::Handler
  PASSED_ENV = %w[PATH HOME LANG LC_ALL TMPDIR].freeze

  def execute
    command = Shellwords.split(config("command").to_s)
    raise "Missing required config: command" if command.empty?

    Dir.mktmpdir("archsight-command") do |tmp|
      output_path = File.join(tmp, "output.yaml")
      progress.update("Running #{command.first}")
      out, err, status = Open3.capture3(environment(output_path), *command, chdir: working_directory, unsetenv_others: true)
      raise "Command failed (exit #{status.exitstatus}): #{last_lines(err.empty? ? out : err)}" unless status.success?

      record_declared_outputs
      write_output(program_output(output_path))
    end
  rescue Errno::ENOENT => e
    raise "Command not found: #{e.message}"
  end

  private

  # What the program wrote to ARCHSIGHT_OUTPUT_PATH (a temporary file), as written: it must be YAML documents that
  # are mappings, and stays byte for byte as it is (comments, order, no added annotations)
  def program_output(output_path)
    return "" unless File.file?(output_path)

    text = File.read(output_path)
    YAML.load_stream(text).compact.each do |document|
      raise "#{import_resource.name}: the command wrote a document that is not a resource" unless document.is_a?(Hash)
    end
    text.end_with?("\n") || text.empty? ? text : "#{text}\n"
  rescue Psych::SyntaxError => e
    raise "The command wrote invalid YAML: #{e.message}"
  end

  # The output file is the import's own: written whole (not through the shared writer, which would drop the
  # unmarked documents when another import flushes the file) and recorded as an output, so a changed outputPath
  # removes the old file. Recorded before the marker is built, so the marker lists it.
  def write_output(text)
    rel_path = Archsight::Import.output_path(import_resource)
    record_output(rel_path)
    write_file(rel_path, text + YAML.dump(self_marker))
  end

  def environment(output_path)
    passed = PASSED_ENV + config("env").to_s.split(",").map(&:strip).reject(&:empty?)
    env = passed.to_h { |name| [name, ENV.fetch(name, nil)] }.compact
    env.merge(
      "ARCHSIGHT_RESOURCES_DIR" => File.expand_path(resources_dir),
      "ARCHSIGHT_CACHE_DIR" => cache_root,
      "ARCHSIGHT_IMPORT_NAME" => import_resource.name,
      "ARCHSIGHT_OUTPUT_PATH" => File.expand_path(output_path)
    )
  end

  def working_directory
    workdir = config("workdir")
    if workdir
      root = File.expand_path(resources_dir)
      path = File.expand_path(workdir, root)
      return path if path == root || path.start_with?("#{root}/")

      raise "workdir #{workdir} is outside the resources directory"
    end

    toplevel, _, status = Open3.capture3("git", "rev-parse", "--show-toplevel", chdir: resources_dir)
    status.success? ? toplevel.strip : File.expand_path(resources_dir)
  rescue Errno::ENOENT
    File.expand_path(resources_dir)
  end

  def record_declared_outputs
    patterns = config("outputs").to_s.split(",").map(&:strip).reject(&:empty?)
    root = File.expand_path(resources_dir)
    patterns.flat_map { |pattern| Dir.glob(pattern, base: root) }.uniq.each do |file|
      record_output(file) if File.file?(File.join(root, file))
    end
  end

  def last_lines(text)
    text.to_s.lines.last(5).join.strip
  end
end

Archsight::Import::Registry.register("command", Archsight::Import::Handlers::Command)
