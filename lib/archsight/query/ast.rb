# frozen_string_literal: true

# AST module contains all Abstract Syntax Tree node types for the query language
module Archsight::Query::AST
  # Base class for all AST nodes
  class Node
    def accept(visitor)
      raise NotImplementedError
    end
  end

  # Root query node with optional kind filter
  class QueryNode < Node
    attr_reader :kind_filter, :expression

    def initialize(kind_filter, expression)
      @kind_filter = kind_filter # String or nil
      @expression = expression   # Expression node
    end

    def accept(visitor)
      visitor.visit_query(self)
    end
  end

  # Binary logical operation (AND, OR)
  class BinaryOp < Node
    attr_reader :operator, :left, :right

    def initialize(operator, left, right)
      @operator = operator # :and, :or
      @left = left
      @right = right
    end

    def accept(visitor)
      visitor.visit_binary_op(self)
    end
  end

  # Unary NOT operation
  class NotOp < Node
    attr_reader :operand

    def initialize(operand)
      @operand = operand
    end

    def accept(visitor)
      visitor.visit_not_op(self)
    end
  end

  # Annotation condition: annotation_path op value
  class AnnotationCondition < Node
    attr_reader :path, :operator, :value

    def initialize(path, operator, value)
      @path = path         # String (e.g., "activity/status")
      @operator = operator # String (==, !=, =~, >, <, >=, <=)
      @value = value       # StringValue, NumberValue, or RegexValue
    end

    def accept(visitor)
      visitor.visit_annotation_condition(self)
    end
  end

  # Annotation existence condition: annotation_path? (checks if annotation exists)
  class AnnotationExistsCondition < Node
    attr_reader :path

    def initialize(path)
      @path = path # String (e.g., "activity/status")
    end

    def accept(visitor)
      visitor.visit_annotation_exists_condition(self)
    end
  end

  # Annotation "in" condition: annotation_path in (value1, value2, ...)
  class AnnotationInCondition < Node
    attr_reader :path, :values

    def initialize(path, values)
      @path = path     # String (e.g., "repository/artifacts")
      @values = values # Array of StringValue
    end

    def accept(visitor)
      visitor.visit_annotation_in_condition(self)
    end
  end

  # Kind condition: kind == "SomeKind" or kind =~ "pattern"
  class KindCondition < Node
    attr_reader :operator, :value

    def initialize(operator, value)
      @operator = operator # String (==, =~)
      @value = value       # StringValue or RegexValue
    end

    def accept(visitor)
      visitor.visit_kind_condition(self)
    end
  end

  # Kind "in" condition: kind in ("Kind1", "Kind2", ...)
  class KindInCondition < Node
    attr_reader :values

    def initialize(values)
      @values = values # Array of StringValue
    end

    def accept(visitor)
      visitor.visit_kind_in_condition(self)
    end
  end

  # Name condition: name == "value" or name =~ "pattern"
  class NameCondition < Node
    attr_reader :operator, :value

    def initialize(operator, value)
      @operator = operator # String (==, !=, =~)
      @value = value       # StringValue or RegexValue
    end

    def accept(visitor)
      visitor.visit_name_condition(self)
    end
  end

  # Name "in" condition: name in ("name1", "name2", ...)
  class NameInCondition < Node
    attr_reader :values

    def initialize(values)
      @values = values # Array of StringValue
    end

    def accept(visitor)
      visitor.visit_name_in_condition(self)
    end
  end

  # Outgoing direct relation: -> Kind or -> "InstanceName"
  # With optional verb filter: -{verb}> or -{!verb}>
  class OutgoingDirectRelation < Node
    attr_reader :target, :verbs, :exclude_verbs

    def initialize(target, verbs = nil, exclude_verbs = false)
      @target = target               # KindTarget or InstanceTarget
      @verbs = verbs                 # Array of verb strings, or nil for "all verbs"
      @exclude_verbs = exclude_verbs # true = denylist, false = allowlist
    end

    def accept(visitor)
      visitor.visit_outgoing_direct_relation(self)
    end
  end

  # Outgoing transitive relation: ~> Kind or ~> "InstanceName"
  # With optional verb filter: ~{verb}> or ~{!verb}>
  class OutgoingTransitiveRelation < Node
    attr_reader :target, :max_depth, :verbs, :exclude_verbs

    def initialize(target, verbs = nil, exclude_verbs = false, max_depth = 10)
      @target = target
      @verbs = verbs                 # Array of verb strings, or nil for "all verbs"
      @exclude_verbs = exclude_verbs # true = denylist, false = allowlist
      @max_depth = max_depth
    end

    def accept(visitor)
      visitor.visit_outgoing_transitive_relation(self)
    end
  end

  # Incoming direct relation: <- Kind or <- "InstanceName"
  # With optional verb filter: <{verb}- or <{!verb}-
  class IncomingDirectRelation < Node
    attr_reader :target, :verbs, :exclude_verbs

    def initialize(target, verbs = nil, exclude_verbs = false)
      @target = target               # KindTarget or InstanceTarget
      @verbs = verbs                 # Array of verb strings, or nil for "all verbs"
      @exclude_verbs = exclude_verbs # true = denylist, false = allowlist
    end

    def accept(visitor)
      visitor.visit_incoming_direct_relation(self)
    end
  end

  # Incoming transitive relation: <~ Kind or <~ "InstanceName"
  # With optional verb filter: <{verb}~ or <{!verb}~
  class IncomingTransitiveRelation < Node
    attr_reader :target, :max_depth, :verbs, :exclude_verbs

    def initialize(target, verbs = nil, exclude_verbs = false, max_depth = 10)
      @target = target
      @verbs = verbs                 # Array of verb strings, or nil for "all verbs"
      @exclude_verbs = exclude_verbs # true = denylist, false = allowlist
      @max_depth = max_depth
    end

    def accept(visitor)
      visitor.visit_incoming_transitive_relation(self)
    end
  end

  # Relation target: a kind name (identifier)
  class KindTarget
    attr_reader :kind_name

    def initialize(kind_name)
      @kind_name = kind_name
    end
  end

  # Relation target: a specific instance name (string)
  class InstanceTarget
    attr_reader :instance_name

    def initialize(instance_name)
      @instance_name = instance_name
    end
  end

  # Relation target: nothing (no relations)
  # Used with -> # (no outgoing) or <- # (no incoming)
  class NothingTarget
  end

  # Relation target: sub-query result
  # Used with -> $(expr) to match against query results
  class SubqueryTarget
    attr_reader :query

    def initialize(query)
      @query = query # QueryNode - the inner sub-query to evaluate
    end
  end

  # Value types
  class StringValue
    attr_reader :value

    def initialize(value)
      @value = value
    end
  end

  class NumberValue
    attr_reader :value

    def initialize(value)
      @value = value.to_f
    end
  end

  class RegexValue
    attr_reader :pattern, :flags

    def initialize(pattern, flags = "")
      @pattern = pattern
      @flags = flags
    end

    def to_regexp
      options = @flags.include?("i") ? Regexp::IGNORECASE : 0
      Regexp.new(@pattern, options)
    end
  end
end
