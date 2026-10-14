# frozen_string_literal: true

require "archsight/import"

# Registry of import handlers
#
# Handlers register themselves with a name that matches the import/handler annotation.
# The executor looks up handlers by name to instantiate and execute them.
module Archsight::Import::Registry
  @handlers = {}
  @builtin = {}

  class << self
    # Register a handler class with a name
    # @param name [String, Symbol] Handler name (matches import/handler annotation)
    # @param handler_class [Class] Handler class that extends Handler
    # @raise [DuplicateHandlerError] if another class already registered the name
    def register(name, handler_class)
      name = name.to_s
      existing = @handlers[name] || @builtin[name]
      raise Archsight::Import::DuplicateHandlerError, "Import handler '#{name}' is registered twice (#{existing} and #{handler_class})" if existing && existing != handler_class

      @handlers[name] = handler_class
      @builtin[name] = handler_class if builtin_caller?(caller_locations(1, 1)&.first)
    end

    # Register the built-in handlers again after `clear!` (they are only required once per process)
    def restore_builtin!
      @handlers = @builtin.merge(@handlers)
    end

    # Look up a handler class by name
    # @param name [String] Handler name
    # @return [Class, nil] Handler class or nil if not found
    def [](name)
      @handlers[name.to_s]
    end

    # Get handler class for an import resource
    # @param import_resource [Archsight::Resources::Import] Import resource
    # @return [Class] Handler class
    # @raise [UnknownHandlerError] if handler is not registered
    def handler_for(import_resource)
      handler_name = import_resource.annotations["import/handler"]
      handler_class = self[handler_name]

      raise Archsight::Import::UnknownHandlerError, "Unknown import handler: #{handler_name}" unless handler_class

      handler_class
    end

    # Return all grapher handler classes that can handle the given path.
    # Each class opts in by implementing `self.applicable?(path)` returning true/false.
    def handlers_for(path)
      @handlers.values.select do |h|
        h.respond_to?(:applicable?) && begin
          h.applicable?(path)
        rescue Errno::ELOOP, Errno::ENOTDIR
          false
        end
      end
    end

    # Look up a grapher handler by its declared language name.
    # Handler classes opt in by implementing `self.language_name`.
    def handler_for_language(lang)
      @handlers.values.find { |h| h.respond_to?(:language_name) && h.language_name == lang }
    end

    # Reverse lookup: return the registered name for a handler class, or nil.
    def name_for(klass)
      @handlers.key(klass)
    end

    # List all registered handler names
    # @return [Array<String>] Handler names
    def handlers
      @handlers.keys
    end

    # Clear all registered handlers (for testing)
    def clear!
      @handlers = {}
    end

    private

    def builtin_caller?(location)
      location && File.expand_path(location.path).start_with?("#{File.expand_path("handlers", __dir__)}/")
    end
  end
end

# Error raised when an unknown handler is requested
class Archsight::Import::UnknownHandlerError < StandardError; end

# Error raised when two handler classes register the same name
class Archsight::Import::DuplicateHandlerError < StandardError; end
