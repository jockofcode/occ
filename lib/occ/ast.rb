# frozen_string_literal: true

module OCC
  module AST
    # ── Base ────────────────────────────────────────────────────────────────────
    # All nodes carry a source location for error messages.

    class Node
      attr_accessor :location, :ctype
      def initialize(location: nil) = @location = location
    end

    # ── Top-level ────────────────────────────────────────────────────────────────

    class TranslationUnit < Node
      attr_accessor :decls
      def initialize(decls:, **kw) = (super(**kw); @decls = decls)
    end

    # ── Declarations ─────────────────────────────────────────────────────────────

    class Declaration < Node
      attr_accessor :specifiers, :declarators   # declarators: [{name:, type_fn:, init:}]
      def initialize(specifiers:, declarators:, **kw)
        super(**kw)
        @specifiers  = specifiers
        @declarators = declarators
      end
    end

    class FunctionDef < Node
      attr_accessor :specifiers, :name, :params, :body, :return_type_fn, :resolved_return_type, :constructor
      def initialize(specifiers:, name:, params:, body:, return_type_fn:, constructor: false, **kw)
        super(**kw)
        @specifiers     = specifiers
        @name           = name
        @params         = params
        @body           = body
        @return_type_fn = return_type_fn
        @constructor    = constructor
      end
    end

    # A param entry: {name: String|nil, type_fn: proc}
    # (type_fn applied to base specifier type gives the param type)

    # ── Statements ───────────────────────────────────────────────────────────────

    class CompoundStmt < Node
      attr_accessor :items
      def initialize(items:, **kw) = (super(**kw); @items = items)
    end

    class ExprStmt < Node
      attr_accessor :expr
      def initialize(expr:, **kw) = (super(**kw); @expr = expr)
    end

    class IfStmt < Node
      attr_accessor :cond, :then_body, :else_body
      def initialize(cond:, then_body:, else_body: nil, **kw)
        super(**kw); @cond = cond; @then_body = then_body; @else_body = else_body
      end
    end

    class WhileStmt < Node
      attr_accessor :cond, :body
      def initialize(cond:, body:, **kw) = (super(**kw); @cond = cond; @body = body)
    end

    class DoWhileStmt < Node
      attr_accessor :body, :cond
      def initialize(body:, cond:, **kw) = (super(**kw); @body = body; @cond = cond)
    end

    class ForStmt < Node
      attr_accessor :init, :cond, :update, :body
      def initialize(init:, cond:, update:, body:, **kw)
        super(**kw); @init = init; @cond = cond; @update = update; @body = body
      end
    end

    class SwitchStmt < Node
      attr_accessor :expr, :body
      def initialize(expr:, body:, **kw) = (super(**kw); @expr = expr; @body = body)
    end

    class ReturnStmt < Node
      attr_accessor :value
      def initialize(value: nil, **kw) = (super(**kw); @value = value)
    end

    class BreakStmt    < Node; end
    class ContinueStmt < Node; end

    class GotoStmt < Node
      attr_accessor :label
      def initialize(label:, **kw) = (super(**kw); @label = label)
    end

    class LabelStmt < Node
      attr_accessor :name, :stmt
      def initialize(name:, stmt:, **kw) = (super(**kw); @name = name; @stmt = stmt)
    end

    class CaseStmt < Node
      attr_accessor :value, :stmt
      def initialize(value:, stmt:, **kw) = (super(**kw); @value = value; @stmt = stmt)
    end

    class DefaultStmt < Node
      attr_accessor :stmt
      def initialize(stmt:, **kw) = (super(**kw); @stmt = stmt)
    end

    # ── Expressions ──────────────────────────────────────────────────────────────

    class IntLiteral < Node
      attr_accessor :raw, :suffix
      def initialize(raw:, suffix:, **kw) = (super(**kw); @raw = raw; @suffix = suffix)
      def integer_value
        raw.start_with?('0x', '0X') ? raw.to_i(16) :
        raw.start_with?('0') && raw.length > 1 ? raw.to_i(8) :
        raw.to_i
      end
    end

    class FloatLiteral < Node
      attr_accessor :raw, :suffix
      def initialize(raw:, suffix:, **kw) = (super(**kw); @raw = raw; @suffix = suffix)
    end

    class StringLiteral < Node
      attr_accessor :value, :prefix
      def initialize(value:, prefix: nil, **kw) = (super(**kw); @value = value; @prefix = prefix)
    end

    class CharLiteral < Node
      attr_accessor :value, :prefix
      def initialize(value:, prefix: nil, **kw) = (super(**kw); @value = value; @prefix = prefix)
    end

    class Identifier < Node
      attr_accessor :name
      def initialize(name:, **kw) = (super(**kw); @name = name)
    end

    class BinaryOp < Node
      attr_accessor :op, :left, :right
      def initialize(op:, left:, right:, **kw)
        super(**kw); @op = op; @left = left; @right = right
      end
    end

    class UnaryOp < Node
      attr_accessor :op, :operand
      def initialize(op:, operand:, **kw) = (super(**kw); @op = op; @operand = operand)
    end

    class Assign < Node
      attr_accessor :op, :target, :value
      def initialize(op:, target:, value:, **kw)
        super(**kw); @op = op; @target = target; @value = value
      end
    end

    class TernaryOp < Node
      attr_accessor :cond, :then_expr, :else_expr
      def initialize(cond:, then_expr:, else_expr:, **kw)
        super(**kw); @cond = cond; @then_expr = then_expr; @else_expr = else_expr
      end
    end

    class Cast < Node
      attr_accessor :type_spec, :expr
      def initialize(type_spec:, expr:, **kw) = (super(**kw); @type_spec = type_spec; @expr = expr)
    end

    class SizeofExpr < Node
      attr_accessor :operand, :sizeof_val
      def initialize(operand:, **kw) = (super(**kw); @operand = operand)
    end

    class SizeofType < Node
      attr_accessor :type_spec, :sizeof_val
      def initialize(type_spec:, **kw) = (super(**kw); @type_spec = type_spec)
    end

    class AlignofType < Node
      attr_accessor :type_spec
      def initialize(type_spec:, **kw) = (super(**kw); @type_spec = type_spec)
    end

    class CallExpr < Node
      attr_accessor :callee, :args
      def initialize(callee:, args:, **kw) = (super(**kw); @callee = callee; @args = args)
    end

    class IndexExpr < Node
      attr_accessor :array, :index
      def initialize(array:, index:, **kw) = (super(**kw); @array = array; @index = index)
    end

    class MemberExpr < Node
      attr_accessor :expr, :member, :arrow
      def initialize(expr:, member:, arrow:, **kw)
        super(**kw); @expr = expr; @member = member; @arrow = arrow
      end
    end

    class CommaExpr < Node
      attr_accessor :exprs
      def initialize(exprs:, **kw) = (super(**kw); @exprs = exprs)
    end

    # ── Type specifiers (AST-level, not the full type objects) ──────────────────

    class TypeSpec < Node
      attr_accessor :storage, :qualifiers, :type_keywords, :tag_decl, :typedef_name
      def initialize(storage: nil, qualifiers: [], type_keywords: [],
                     tag_decl: nil, typedef_name: nil, **kw)
        super(**kw)
        @storage       = storage
        @qualifiers    = qualifiers
        @type_keywords = type_keywords
        @tag_decl      = tag_decl
        @typedef_name  = typedef_name
      end
    end

    class StructSpec < Node
      attr_accessor :keyword, :tag, :fields
      def initialize(keyword:, tag: nil, fields: nil, **kw)
        super(**kw); @keyword = keyword; @tag = tag; @fields = fields
      end
    end

    class FieldDecl < Node
      attr_accessor :specifiers, :declarators
      def initialize(specifiers:, declarators:, **kw)
        super(**kw); @specifiers = specifiers; @declarators = declarators
      end
    end

    class EnumSpec < Node
      attr_accessor :tag, :enumerators
      def initialize(tag: nil, enumerators: nil, **kw)
        super(**kw); @tag = tag; @enumerators = enumerators
      end
    end

    class Enumerator < Node
      attr_accessor :name, :value
      def initialize(name:, value: nil, **kw) = (super(**kw); @name = name; @value = value)
    end

    class StaticAssert < Node
      attr_accessor :expr, :message
      def initialize(expr:, message:, **kw) = (super(**kw); @expr = expr; @message = message)
    end
  end
end
