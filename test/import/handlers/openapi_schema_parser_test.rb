# frozen_string_literal: true

require "test_helper"
require "archsight/import/handlers/openapi_schema_parser"

class OpenAPISchemaParserTest < Minitest::Test
  def test_skip_utility_schemas
    openapi_doc = {
      "components" => {
        "schemas" => {
          "Server" => { "type" => "object", "properties" => { "id" => { "type" => "string" } } },
          "Error" => { "type" => "object", "properties" => { "message" => { "type" => "string" } } },
          "ErrorResponse" => { "type" => "object", "properties" => { "error" => { "type" => "string" } } },
          "Pagination" => { "type" => "object", "properties" => { "offset" => { "type" => "integer" } } }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    assert_includes result.keys, "Server"
    refute_includes result.keys, "Error"
    refute_includes result.keys, "ErrorResponse"
    refute_includes result.keys, "Pagination"
  end

  def test_normalize_name_strips_crud_suffixes
    openapi_doc = {
      "components" => {
        "schemas" => {
          "ServerCreate" => { "type" => "object", "properties" => { "name" => { "type" => "string" } } },
          "ServerRead" => { "type" => "object", "properties" => { "id" => { "type" => "string" } } },
          "ServerList" => { "type" => "object", "properties" => { "items" => { "type" => "array" } } }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    # All should normalize to "Server"
    assert_equal 1, result.size
    assert_includes result.keys, "Server"
    assert_includes result["Server"]["original_names"], "ServerCreate"
  end

  def test_normalize_name_strips_crud_prefixes
    openapi_doc = {
      "components" => {
        "schemas" => {
          "CreateServer" => { "type" => "object", "properties" => { "name" => { "type" => "string" } } },
          "GetServer" => { "type" => "object", "properties" => { "id" => { "type" => "string" } } }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    assert_equal 1, result.size
    assert_includes result.keys, "Server"
  end

  def test_singularize_plural_names
    openapi_doc = {
      "components" => {
        "schemas" => {
          "Servers" => { "type" => "object", "properties" => { "items" => { "type" => "array" } } },
          "Entries" => { "type" => "object", "properties" => { "data" => { "type" => "string" } } }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    assert_includes result.keys, "Server"
    assert_includes result.keys, "Entry"
  end

  def test_keep_plural_exceptions
    openapi_doc = {
      "components" => {
        "schemas" => {
          "Status" => { "type" => "object", "properties" => { "state" => { "type" => "string" } } },
          "Address" => { "type" => "object", "properties" => { "ip" => { "type" => "string" } } }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    # These should NOT be singularized
    assert_includes result.keys, "Status"
    assert_includes result.keys, "Address"
  end

  def test_extract_simple_properties
    openapi_doc = {
      "components" => {
        "schemas" => {
          "Server" => {
            "type" => "object",
            "required" => %w[name],
            "properties" => {
              "id" => { "type" => "string", "format" => "uuid", "description" => "Server ID" },
              "name" => { "type" => "string", "description" => "Server name" },
              "cores" => { "type" => "integer" }
            }
          }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    server = result["Server"]
    props = server["properties"]

    assert_equal 3, props.size

    id_prop = props.find { |p| p["name"] == "id" }

    assert_equal "string", id_prop["type"]
    assert_equal "uuid", id_prop["format"]
    assert_equal "Server ID", id_prop["description"]
    refute id_prop["required"]

    name_prop = props.find { |p| p["name"] == "name" }

    assert name_prop["required"]
  end

  def test_resolve_refs
    openapi_doc = {
      "components" => {
        "schemas" => {
          "Server" => {
            "type" => "object",
            "properties" => {
              "properties" => { "$ref" => "#/components/schemas/ServerProperties" }
            }
          },
          "ServerProperties" => {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string" },
              "cores" => { "type" => "integer" }
            }
          }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    server = result["Server"]
    props = server["properties"]

    # Should have nested properties from ref
    assert(props.any? { |p| p["name"] == "properties.name" })
    assert(props.any? { |p| p["name"] == "properties.cores" })
  end

  def test_handle_allof_composition
    openapi_doc = {
      "components" => {
        "schemas" => {
          "Server" => {
            "allOf" => [
              {
                "type" => "object",
                "properties" => {
                  "id" => { "type" => "string" }
                }
              },
              {
                "type" => "object",
                "properties" => {
                  "name" => { "type" => "string" }
                }
              }
            ]
          }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    server = result["Server"]
    props = server["properties"]

    assert_equal 2, props.size
    assert(props.any? { |p| p["name"] == "id" })
    assert(props.any? { |p| p["name"] == "name" })
  end

  def test_handle_cycle_detection
    openapi_doc = {
      "components" => {
        "schemas" => {
          "Node" => {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string" },
              "children" => {
                "type" => "array",
                "items" => { "$ref" => "#/components/schemas/Node" }
              }
            }
          }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    # Should not infinite loop
    result = parser.parse

    assert_includes result.keys, "Node"
  end

  def test_max_depth_limit
    openapi_doc = {
      "components" => {
        "schemas" => {
          "Level0" => {
            "type" => "object",
            "properties" => {
              "level1" => { "$ref" => "#/components/schemas/Level1" }
            }
          },
          "Level1" => {
            "type" => "object",
            "properties" => {
              "level2" => { "$ref" => "#/components/schemas/Level2" }
            }
          },
          "Level2" => {
            "type" => "object",
            "properties" => {
              "level3" => { "$ref" => "#/components/schemas/Level3" }
            }
          },
          "Level3" => {
            "type" => "object",
            "properties" => {
              "level4" => { "$ref" => "#/components/schemas/Level4" }
            }
          },
          "Level4" => {
            "type" => "object",
            "properties" => {
              "value" => { "type" => "string" }
            }
          }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    # Level0 should exist but deeply nested properties should be limited
    assert_includes result.keys, "Level0"
  end

  def test_generate_field_docs
    properties = [
      { "name" => "id", "type" => "string", "format" => "uuid", "required" => false, "description" => "Server ID" },
      { "name" => "name", "type" => "string", "format" => nil, "required" => true, "description" => "Server name" }
    ]

    docs = Archsight::Import::Handlers::OpenAPISchemaParser.generate_field_docs(properties)

    assert_includes docs, "## Fields"
    assert_includes docs, "| `id` | string (uuid) | No | Server ID |"
    assert_includes docs, "| `name` | string | Yes | Server name |"
  end

  def test_generate_field_docs_empty
    docs = Archsight::Import::Handlers::OpenAPISchemaParser.generate_field_docs([])

    assert_equal "", docs
  end

  def test_array_of_refs
    openapi_doc = {
      "components" => {
        "schemas" => {
          "ServerList" => {
            "type" => "object",
            "properties" => {
              "items" => {
                "type" => "array",
                "items" => { "$ref" => "#/components/schemas/Server" }
              }
            }
          },
          "Server" => {
            "type" => "object",
            "properties" => {
              "id" => { "type" => "string" }
            }
          }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    server = result["Server"]
    props = server["properties"]

    # ServerList normalizes to Server, so we just check Server exists
    assert_includes result.keys, "Server"
    assert(props.any? { |p| %w[id items].include?(p["name"]) })
  end

  def test_tracks_original_names
    openapi_doc = {
      "components" => {
        "schemas" => {
          "Server" => { "type" => "object", "properties" => { "id" => { "type" => "string" } } },
          "ServerCreate" => { "type" => "object", "properties" => { "name" => { "type" => "string" } } },
          "ServerRead" => { "type" => "object", "properties" => { "state" => { "type" => "string" } } }
        }
      }
    }

    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    result = parser.parse

    server = result["Server"]
    original_names = server["original_names"]

    # First schema wins for properties, but all names are tracked
    assert_includes original_names, "Server"
    assert_includes original_names, "ServerCreate"
    assert_includes original_names, "ServerRead"
  end
end
