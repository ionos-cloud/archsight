# frozen_string_literal: true

require "test_helper"
require "archsight/import/registry"
require "archsight/import/handler"

class RegistryTest < Minitest::Test
  def setup
    # Clear registry before each test
    Archsight::Import::Registry.clear!
  end

  def test_register_and_lookup
    Archsight::Import::Registry.register("test", TestHandler)

    assert_equal TestHandler, Archsight::Import::Registry["test"]
  end

  def test_lookup_nonexistent_returns_nil
    assert_nil Archsight::Import::Registry["nonexistent"]
  end

  def test_register_with_symbol
    Archsight::Import::Registry.register(:symbol_handler, TestHandler)

    assert_equal TestHandler, Archsight::Import::Registry["symbol_handler"]
    assert_equal TestHandler, Archsight::Import::Registry[:symbol_handler]
  end

  def test_handlers_returns_registered_names
    Archsight::Import::Registry.register("handler1", TestHandler)
    Archsight::Import::Registry.register("handler2", TestHandler)

    handlers = Archsight::Import::Registry.handlers

    assert_includes handlers, "handler1"
    assert_includes handlers, "handler2"
  end

  def test_handler_for_returns_class
    Archsight::Import::Registry.register("test", TestHandler)

    import = MockImport.new("import/handler" => "test")
    handler_class = Archsight::Import::Registry.handler_for(import)

    assert_equal TestHandler, handler_class
  end

  def test_handler_for_raises_on_unknown
    import = MockImport.new("import/handler" => "unknown")

    assert_raises(Archsight::Import::UnknownHandlerError) do
      Archsight::Import::Registry.handler_for(import)
    end
  end

  def test_clear_removes_all_handlers
    Archsight::Import::Registry.register("test", TestHandler)
    Archsight::Import::Registry.clear!

    assert_nil Archsight::Import::Registry["test"]
    assert_empty Archsight::Import::Registry.handlers
  end

  class TestHandler < Archsight::Import::Handler
    def execute; end
  end

  class MockImport
    attr_reader :annotations

    def initialize(annotations = {})
      @annotations = annotations
    end
  end
end
