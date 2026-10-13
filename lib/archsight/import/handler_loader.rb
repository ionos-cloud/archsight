# frozen_string_literal: true

require "archsight/import"

# Loads import handlers: the built-in ones shipped with the gem, and the handlers of the resources repository that an
# Import declares with `import/handlerPath` (a Ruby file relative to the resources directory, like
# `import/outputPath`). Used by `archsight import`, `lint` and `web`, so every command knows the same handler names.
module Archsight::Import::HandlerLoader
  BUILTIN_DIR = File.expand_path("handlers", __dir__)

  # A problem with a local handler file, reported by the linter and by `archsight import`
  Problem = Struct.new(:import, :message) do
    def to_s
      "#{import.path_ref}: Import '#{import.name}' #{message}"
    end
  end

  class << self
    # Require the built-in handlers. Idempotent; registers them again when a test cleared the registry.
    def load_builtin!
      Dir.glob(File.join(BUILTIN_DIR, "*.rb")).each { |file| require file }
      Archsight::Import::Registry.restore_builtin!
    end

    # Load the built-in handlers and every handler file the Imports of the database declare
    # @param database [Archsight::Database]
    # @param resources_dir [String] directory `import/handlerPath` is relative to
    # @return [Array<Problem>] files that are missing, outside the resources directory, fail to load or do not register
    #   the handler named in `import/handler`
    def load(database, resources_dir: database.path)
      load_builtin!
      imports = database.instances_by_kind("Import")&.values || []
      imports.select { |imp| imp.annotations["import/handlerPath"] }.flat_map { |imp| load_for(imp, resources_dir) }
    end

    # Absolute path of the handler file of an Import, nil when it points outside the resources directory
    def handler_file(import, resources_dir)
      Archsight::Import.resources_path(resources_dir, import.annotations["import/handlerPath"])
    end

    private

    def load_for(import, resources_dir)
      file = handler_file(import, resources_dir)
      return [Problem.new(import, "has import/handlerPath '#{import.annotations["import/handlerPath"]}' outside the resources directory")] unless file
      return [Problem.new(import, "has import/handlerPath '#{import.annotations["import/handlerPath"]}' that does not exist")] unless File.file?(file)

      problem = require_file(import, file)
      return [problem] if problem

      name = import.annotations["import/handler"]
      return [] if name.nil? || Archsight::Import::Registry[name]

      [Problem.new(import, "loads #{import.annotations["import/handlerPath"]}, which does not register the handler '#{name}'")]
    end

    def require_file(import, file)
      require file
      nil
    rescue ScriptError, StandardError => e
      Problem.new(import, "cannot load #{import.annotations["import/handlerPath"]}: #{e.class}: #{e.message.lines.first&.strip}")
    end
  end
end
