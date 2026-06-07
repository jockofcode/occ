# frozen_string_literal: true

module OCC
  # Recursive-descent parser for C11.
  #
  # The typedef ambiguity (is `foo * bar` a declaration or an expression?)
  # is resolved by tracking a set of known typedef names in @typedefs.
  class Parser
    STORAGE_CLASSES   = %i[kw_typedef kw_extern kw_static kw_auto kw_register
                           kw__Thread_local].freeze
    TYPE_QUALIFIERS   = %i[kw_const kw_volatile kw_restrict kw__Atomic].freeze
    FUNC_SPECIFIERS   = %i[kw_inline kw__Noreturn].freeze
    BASIC_TYPE_SPECS  = %i[kw_void kw_char kw_short kw_int kw_long kw_float
                           kw_double kw_signed kw_unsigned kw__Bool
                           kw__Complex kw__Imaginary].freeze

    # Operator precedence table for expression parsing (Pratt style).
    # Values are [binding_power, right_associative?]
    BINOP_PREC = {
      star:           [12, false],
      slash:          [12, false],
      percent:        [12, false],
      plus:           [11, false],
      minus:          [11, false],
      lshift:         [10, false],
      rshift:         [10, false],
      lt:             [9,  false],
      leq:            [9,  false],
      gt:             [9,  false],
      geq:            [9,  false],
      eq:             [8,  false],
      neq:            [8,  false],
      amp:            [7,  false],
      caret:          [6,  false],
      pipe:           [5,  false],
      logical_and:    [4,  false],
      logical_or:     [3,  false]
    }.freeze

    ASSIGN_OPS = %i[assign plus_assign minus_assign star_assign slash_assign
                    percent_assign amp_assign pipe_assign caret_assign
                    lshift_assign rshift_assign].freeze

    def initialize(tokens)
      @tokens  = tokens.reject { |t| t.type == :eof } + [tokens.find { |t| t.type == :eof } || tokens.last]
      @pos     = 0
      @typedefs = Set.new   # names declared via typedef
    end

    def parse
      decls = []
      decls << parse_external_declaration until cur.eof?
      AST::TranslationUnit.new(decls: decls, location: decls.first&.location)
    end

    private

    # ── Token helpers ─────────────────────────────────────────────────────────

    def cur           = @tokens[@pos]
    def peek(n = 1)   = @tokens[@pos + n]
    def loc           = cur.location

    def advance
      t = @tokens[@pos]
      @pos += 1 unless t.eof?
      t
    end

    def expect(type)
      raise ParseError.new("expected #{type}, got #{cur.type} ('#{cur.value}')", cur.location) unless cur.type == type
      advance
    end

    def match(*types)
      return false unless types.include?(cur.type)
      advance
      true
    end

    def cur?(type) = cur.type == type
    def cur_any?(*types) = types.include?(cur.type)

    # ── External declarations ─────────────────────────────────────────────────

    def parse_external_declaration
      l = loc

      if cur?(:kw__Static_assert)
        return parse_static_assert
      end

      specs = parse_declaration_specifiers
      return AST::Declaration.new(specifiers: specs, declarators: [], location: l) if cur?(:semicolon) && advance

      # Parse the first declarator to determine if this is a function definition
      name, type_fn, params = parse_declarator(allow_abstract: false)

      if params && cur?(:lbrace)
        # Function definition
        body = parse_compound_statement
        @typedefs << name if specs.storage == :typedef
        return AST::FunctionDef.new(
          specifiers: specs, name: name, params: params,
          body: body, return_type_fn: type_fn, location: l
        )
      end

      # Declaration with possible initialiser
      init = parse_initializer if match(:assign)
      declarators = [{ name: name, type_fn: type_fn, init: init }]

      while match(:comma)
        n, fn, _p = parse_declarator(allow_abstract: false)
        ini = parse_initializer if match(:assign)
        declarators << { name: n, type_fn: fn, init: ini }
      end

      @typedefs << name if specs.storage == :typedef

      expect(:semicolon)
      AST::Declaration.new(specifiers: specs, declarators: declarators, location: l)
    end

    # ── Declaration specifiers ────────────────────────────────────────────────

    def parse_declaration_specifiers
      l = loc
      spec = AST::TypeSpec.new(location: l)

      loop do
        case cur.type
        when *STORAGE_CLASSES
          spec.storage = cur.type.to_s.sub('kw_', '').to_sym
          advance
        when *TYPE_QUALIFIERS
          spec.qualifiers << cur.type.to_s.sub('kw_', '').to_sym
          advance
        when *FUNC_SPECIFIERS
          advance  # recorded but not yet used beyond tracking
        when :kw__Alignas
          advance; expect(:lparen); parse_type_name_or_expr; expect(:rparen)
        when *BASIC_TYPE_SPECS
          spec.type_keywords << cur.type.to_s.sub('kw_', '').to_sym
          advance
        when :kw_struct, :kw_union
          spec.tag_decl = parse_struct_or_union
          break
        when :kw_enum
          spec.tag_decl = parse_enum
          break
        when :ident
          # Typedef name – only if it's a known typedef and no conflicting type keyword
          if @typedefs.include?(cur.value) && spec.type_keywords.empty? && spec.tag_decl.nil?
            spec.typedef_name = cur.value
            advance
          else
            break
          end
        else
          break
        end
      end

      spec
    end

    def parse_struct_or_union
      l = loc
      keyword = advance.type   # :kw_struct or :kw_union

      tag = cur?(:ident) ? advance.value : nil

      fields = nil
      if cur?(:lbrace)
        advance
        fields = []
        fields << parse_struct_declaration until cur?(:rbrace) || cur.eof?
        expect(:rbrace)
      end

      AST::StructSpec.new(keyword: keyword, tag: tag, fields: fields, location: l)
    end

    def parse_struct_declaration
      l = loc
      specs = parse_declaration_specifiers
      declarators = []
      unless cur?(:semicolon)
        n, fn, _ = parse_declarator
        # Bitfield: optional :width after declarator name (C11 §6.7.2.1)
        bw = nil
        if cur?(:colon) && peek.type != :colon
          advance   # consume ':'
          bw = parse_assignment_expr   # save bitwidth expression
        end
        declarators << { name: n, type_fn: fn, bitwidth: bw }
        while match(:comma)
          n, fn, _ = parse_declarator
          bw = nil
          if cur?(:colon) && peek.type != :colon
            advance
            bw = parse_assignment_expr
          end
          declarators << { name: n, type_fn: fn, bitwidth: bw }
        end
      end
      expect(:semicolon)
      AST::FieldDecl.new(specifiers: specs, declarators: declarators, location: l)
    end

    def parse_enum
      l = loc
      advance  # consume 'enum'
      tag = cur?(:ident) ? advance.value : nil

      enumerators = nil
      if cur?(:lbrace)
        advance
        enumerators = []
        until cur?(:rbrace) || cur.eof?
          name = expect(:ident).value
          val  = match(:assign) ? parse_assignment_expr : nil
          enumerators << AST::Enumerator.new(name: name, value: val, location: l)
          break unless match(:comma)
          break if cur?(:rbrace)
        end
        expect(:rbrace)
      end

      AST::EnumSpec.new(tag: tag, enumerators: enumerators, location: l)
    end

    # ── Declarator ─────────────────────────────────────────────────────────────
    #
    # Returns [name_or_nil, type_modifier_fn, params_or_nil]
    # type_modifier_fn: base_type -> derived_type
    # params_or_nil: present only for direct function declarators

    def parse_declarator(allow_abstract: true)
      # Collect pointer prefix levels (these are innermost in the derived type)
      ptr_levels = []
      while cur?(:star)
        advance
        quals = []
        while TYPE_QUALIFIERS.include?(cur.type)
          quals << cur.type.to_s.sub('kw_', '').to_sym
          advance
        end
        ptr_levels << quals
      end

      ptr_fn = build_pointer_fn(ptr_levels)

      # Direct declarator
      if cur?(:lparen) && !lookahead_is_param_list?
        advance  # consume (
        inner_name, inner_fn, inner_params = parse_declarator(allow_abstract: allow_abstract)
        expect(:rparen)

        outer_postfixes, outer_params = parse_declarator_postfixes
        outer_fn = build_postfix_fn(outer_postfixes)

        combined_fn = ->(base) { inner_fn.call(outer_fn.call(ptr_fn.call(base))) }
        [inner_name, combined_fn, inner_params || outer_params]
      else
        name = nil
        if cur?(:ident)
          name = advance.value
        elsif !allow_abstract
          raise ParseError.new("expected declarator name", loc)
        end

        postfixes, params = parse_declarator_postfixes
        postfix_fn = build_postfix_fn(postfixes)

        combined_fn = ->(base) { postfix_fn.call(ptr_fn.call(base)) }
        [name, combined_fn, params]
      end
    end

    # Returns true when we are at a '(' that starts a parameter list
    # rather than a grouped declarator.
    def lookahead_is_param_list?
      return false unless cur?(:lparen)
      # Look one token ahead: if it's a type keyword, typedef name, or ')', it's params
      nxt = peek
      BASIC_TYPE_SPECS.include?(nxt.type) ||
        STORAGE_CLASSES.include?(nxt.type) ||
        TYPE_QUALIFIERS.include?(nxt.type) ||
        nxt.type == :kw_struct || nxt.type == :kw_union || nxt.type == :kw_enum ||
        nxt.type == :rparen ||
        nxt.type == :ellipsis ||
        (nxt.type == :ident && @typedefs.include?(nxt.value))
    end

    # Returns [postfix_list, params_or_nil]
    # postfix_list entries: :array_unknown | [:array, size_expr] | [:function, params]
    def parse_declarator_postfixes
      postfixes = []
      params    = nil

      loop do
        case cur.type
        when :lbracket
          advance
          if cur?(:rbracket)
            advance
            postfixes << :array_unknown
          elsif cur?(:star)
            advance; expect(:rbracket)
            postfixes << :array_vla
          else
            size = parse_assignment_expr
            expect(:rbracket)
            postfixes << [:array, size]
          end
        when :lparen
          advance
          p = parse_param_list
          expect(:rparen)
          params = p
          postfixes << [:function, p]
          break  # only one function suffix allowed as a direct declarator
        else
          break
        end
      end

      [postfixes, params]
    end

    def parse_param_list
      params   = []
      variadic = false

      if cur?(:rparen)
        return { params: params, variadic: variadic }
      end

      if cur?(:kw_void) && peek.type == :rparen
        advance
        return { params: [], variadic: false }
      end

      loop do
        if cur?(:ellipsis)
          advance
          variadic = true
          break
        end

        specs = parse_declaration_specifiers
        n, fn, _p = parse_declarator
        params << { name: n, specs: specs, type_fn: fn }

        break unless match(:comma)
      end

      { params: params, variadic: variadic }
    end

    def build_pointer_fn(levels)
      return ->(t) { t } if levels.empty?
      ->(base) {
        type = base
        levels.each { |quals| type = { kind: :pointer, base: type, qualifiers: quals } }
        type
      }
    end

    def build_postfix_fn(postfixes)
      return ->(t) { t } if postfixes.empty?
      ->(base) {
        type = base
        postfixes.each do |pf|
          type = case pf
                 when :array_unknown then { kind: :array, element: type, size: nil }
                 when :array_vla     then { kind: :array, element: type, size: :vla }
                 when Array
                   case pf[0]
                   when :array    then { kind: :array,    element: type, size: pf[1] }
                   when :function then { kind: :function, return: type,  params: pf[1] }
                   end
                 end
        end
        type
      }
    end

    def parse_type_name_or_expr
      if is_type_start?
        specs = parse_declaration_specifiers
        _, fn, _ = parse_declarator
        { kind: :type, specs: specs, type_fn: fn }
      else
        parse_assignment_expr
      end
    end

    def is_type_start?
      BASIC_TYPE_SPECS.include?(cur.type) ||
        STORAGE_CLASSES.include?(cur.type) ||
        TYPE_QUALIFIERS.include?(cur.type) ||
        cur_any?(:kw_struct, :kw_union, :kw_enum) ||
        (cur?(:ident) && @typedefs.include?(cur.value))
    end

    # ── Initialiser ───────────────────────────────────────────────────────────

    def parse_initializer
      if cur?(:lbrace)
        l = loc; advance
        inits = []
        until cur?(:rbrace) || cur.eof?
          designators = []
          while cur?(:lbracket) || cur?(:dot)
            if match(:lbracket)
              designators << [:index, parse_assignment_expr]
              expect(:rbracket)
            else
              advance  # .
              designators << [:field, expect(:ident).value]
            end
            match(:assign)
          end
          val = parse_initializer
          inits << { designators: designators, value: val }
          break unless match(:comma)
        end
        expect(:rbrace)
        { kind: :initializer_list, items: inits, location: l }
      else
        parse_assignment_expr
      end
    end

    # ── Statements ────────────────────────────────────────────────────────────

    def parse_statement
      l = loc
      case cur.type
      when :lbrace
        parse_compound_statement
      when :kw_if
        parse_if_statement
      when :kw_while
        parse_while_statement
      when :kw_do
        parse_do_while_statement
      when :kw_for
        parse_for_statement
      when :kw_switch
        parse_switch_statement
      when :kw_return
        advance
        val = cur?(:semicolon) ? nil : parse_expr
        expect(:semicolon)
        AST::ReturnStmt.new(value: val, location: l)
      when :kw_break
        advance; expect(:semicolon)
        AST::BreakStmt.new(location: l)
      when :kw_continue
        advance; expect(:semicolon)
        AST::ContinueStmt.new(location: l)
      when :kw_goto
        advance
        lbl = expect(:ident).value
        expect(:semicolon)
        AST::GotoStmt.new(label: lbl, location: l)
      when :kw_case
        advance
        val = parse_assignment_expr
        expect(:colon)
        stmt = parse_statement
        AST::CaseStmt.new(value: val, stmt: stmt, location: l)
      when :kw_default
        advance; expect(:colon)
        stmt = parse_statement
        AST::DefaultStmt.new(stmt: stmt, location: l)
      when :kw__Static_assert
        parse_static_assert
      when :semicolon
        advance
        AST::ExprStmt.new(expr: nil, location: l)
      when :ident
        # Label or expression-statement
        if peek.type == :colon
          name = advance.value
          advance  # :
          stmt = parse_statement
          AST::LabelStmt.new(name: name, stmt: stmt, location: l)
        else
          parse_expr_or_declaration_statement
        end
      else
        if is_type_start?
          parse_expr_or_declaration_statement
        else
          expr = parse_expr
          expect(:semicolon)
          AST::ExprStmt.new(expr: expr, location: l)
        end
      end
    end

    def parse_compound_statement
      l = loc
      expect(:lbrace)
      items = []
      until cur?(:rbrace) || cur.eof?
        items << (is_type_start? || cur?(:kw__Static_assert) ? parse_block_declaration : parse_statement)
      end
      expect(:rbrace)
      AST::CompoundStmt.new(items: items, location: l)
    end

    def parse_block_declaration
      l = loc
      if cur?(:kw__Static_assert)
        return parse_static_assert
      end
      specs = parse_declaration_specifiers
      declarators = []
      unless cur?(:semicolon)
        n, fn, _p = parse_declarator(allow_abstract: false)
        init = parse_initializer if match(:assign)
        declarators << { name: n, type_fn: fn, init: init }
        @typedefs << n if specs.storage == :typedef
        while match(:comma)
          n2, fn2, _ = parse_declarator(allow_abstract: false)
          ini2 = parse_initializer if match(:assign)
          declarators << { name: n2, type_fn: fn2, init: ini2 }
          @typedefs << n2 if specs.storage == :typedef
        end
      end
      expect(:semicolon)
      AST::Declaration.new(specifiers: specs, declarators: declarators, location: l)
    end

    def parse_expr_or_declaration_statement
      if is_type_start?
        parse_block_declaration
      else
        l = loc
        expr = parse_expr
        expect(:semicolon)
        AST::ExprStmt.new(expr: expr, location: l)
      end
    end

    def parse_if_statement
      l = loc; advance  # 'if'
      expect(:lparen)
      cond = parse_expr
      expect(:rparen)
      then_body = parse_statement
      else_body = nil
      if match(:kw_else)
        else_body = parse_statement
      end
      AST::IfStmt.new(cond: cond, then_body: then_body, else_body: else_body, location: l)
    end

    def parse_while_statement
      l = loc; advance
      expect(:lparen); cond = parse_expr; expect(:rparen)
      body = parse_statement
      AST::WhileStmt.new(cond: cond, body: body, location: l)
    end

    def parse_do_while_statement
      l = loc; advance
      body = parse_statement
      expect(:kw_while)
      expect(:lparen); cond = parse_expr; expect(:rparen)
      expect(:semicolon)
      AST::DoWhileStmt.new(body: body, cond: cond, location: l)
    end

    def parse_for_statement
      l = loc; advance
      expect(:lparen)
      init = if cur?(:semicolon)
               advance; nil
             elsif is_type_start?
               parse_block_declaration
             else
               e = parse_expr; expect(:semicolon); AST::ExprStmt.new(expr: e, location: l)
             end
      cond   = cur?(:semicolon) ? nil : parse_expr; expect(:semicolon)
      update = cur?(:rparen)    ? nil : parse_expr
      expect(:rparen)
      body   = parse_statement
      AST::ForStmt.new(init: init, cond: cond, update: update, body: body, location: l)
    end

    def parse_switch_statement
      l = loc; advance
      expect(:lparen); expr = parse_expr; expect(:rparen)
      body = parse_statement
      AST::SwitchStmt.new(expr: expr, body: body, location: l)
    end

    def parse_static_assert
      l = loc; advance  # _Static_assert
      expect(:lparen)
      expr = parse_assignment_expr
      expect(:comma)
      msg = expect(:string_lit).value[:value]
      expect(:rparen)
      expect(:semicolon)
      AST::StaticAssert.new(expr: expr, message: msg, location: l)
    end

    # ── Expressions ───────────────────────────────────────────────────────────

    def parse_expr
      l   = loc
      lhs = parse_assignment_expr
      return lhs unless cur?(:comma)

      exprs = [lhs]
      while match(:comma)
        exprs << parse_assignment_expr
      end
      AST::CommaExpr.new(exprs: exprs, location: l)
    end

    def parse_assignment_expr
      l   = loc
      lhs = parse_ternary_expr

      if ASSIGN_OPS.include?(cur.type)
        op  = advance.type
        rhs = parse_assignment_expr   # right-associative
        return AST::Assign.new(op: op, target: lhs, value: rhs, location: l)
      end

      lhs
    end

    def parse_ternary_expr
      l    = loc
      cond = parse_binop_expr(0)

      if match(:question)
        then_expr = parse_expr
        expect(:colon)
        else_expr = parse_ternary_expr
        return AST::TernaryOp.new(cond: cond, then_expr: then_expr, else_expr: else_expr, location: l)
      end

      cond
    end

    def parse_binop_expr(min_prec)
      l    = loc
      left = parse_cast_expr

      loop do
        prec_info = BINOP_PREC[cur.type]
        break unless prec_info
        prec, right_assoc = prec_info
        break if prec < min_prec

        op    = advance.type
        right = parse_binop_expr(right_assoc ? prec : prec + 1)
        left  = AST::BinaryOp.new(op: op, left: left, right: right, location: l)
      end

      left
    end

    def parse_cast_expr
      # Is this a cast? (type-name) cast-expression
      if cur?(:lparen) && cast_lookahead?
        l = loc; advance
        type_spec = parse_type_name
        expect(:rparen)
        # Compound literal: (type-name) { ... }
        if cur?(:lbrace)
          init = parse_initializer
          return AST::Cast.new(type_spec: type_spec, expr: init, location: l)
        end
        expr = parse_cast_expr
        return AST::Cast.new(type_spec: type_spec, expr: expr, location: l)
      end

      parse_unary_expr
    end

    def cast_lookahead?
      saved_pos = @pos
      begin
        advance  # consume the (
        is_type_start? && balanced_type_name_followed_by_rparen?
      rescue StandardError
        false
      ensure
        @pos = saved_pos
      end
    end

    def balanced_type_name_followed_by_rparen?
      depth = 1
      pos   = @pos
      loop do
        break if pos >= @tokens.length
        case @tokens[pos].type
        when :lparen then depth += 1
        when :rparen
          depth -= 1
          return true if depth.zero?
        when :eof then return false
        end
        pos += 1
      end
      false
    end

    def parse_type_name
      specs = parse_declaration_specifiers
      _, fn, _ = parse_declarator
      { specs: specs, type_fn: fn }
    end

    def parse_unary_expr
      l = loc
      case cur.type
      when :increment
        advance; AST::UnaryOp.new(op: :pre_inc, operand: parse_unary_expr, location: l)
      when :decrement
        advance; AST::UnaryOp.new(op: :pre_dec, operand: parse_unary_expr, location: l)
      when :amp
        advance; AST::UnaryOp.new(op: :addr_of, operand: parse_cast_expr, location: l)
      when :star
        advance; AST::UnaryOp.new(op: :deref, operand: parse_cast_expr, location: l)
      when :plus
        advance; AST::UnaryOp.new(op: :unary_plus, operand: parse_cast_expr, location: l)
      when :minus
        advance; AST::UnaryOp.new(op: :unary_minus, operand: parse_cast_expr, location: l)
      when :tilde
        advance; AST::UnaryOp.new(op: :bit_not, operand: parse_cast_expr, location: l)
      when :exclaim
        advance; AST::UnaryOp.new(op: :logical_not, operand: parse_cast_expr, location: l)
      when :kw_sizeof
        advance
        if cur?(:lparen) && cast_lookahead?
          advance
          tn = parse_type_name
          expect(:rparen)
          AST::SizeofType.new(type_spec: tn, location: l)
        else
          AST::SizeofExpr.new(operand: parse_unary_expr, location: l)
        end
      when :kw__Alignof
        advance; expect(:lparen)
        tn = parse_type_name
        expect(:rparen)
        AST::AlignofType.new(type_spec: tn, location: l)
      else
        parse_postfix_expr
      end
    end

    def parse_postfix_expr
      l    = loc
      expr = parse_primary_expr

      loop do
        case cur.type
        when :lbracket
          advance
          idx = parse_expr
          expect(:rbracket)
          expr = AST::IndexExpr.new(array: expr, index: idx, location: l)
        when :lparen
          advance
          args = []
          unless cur?(:rparen)
            args << parse_assignment_expr
            while match(:comma)
              args << parse_assignment_expr
            end
          end
          expect(:rparen)
          expr = AST::CallExpr.new(callee: expr, args: args, location: l)
        when :dot
          advance
          member = expect(:ident).value
          expr = AST::MemberExpr.new(expr: expr, member: member, arrow: false, location: l)
        when :arrow
          advance
          member = expect(:ident).value
          expr = AST::MemberExpr.new(expr: expr, member: member, arrow: true, location: l)
        when :increment
          advance; expr = AST::UnaryOp.new(op: :post_inc, operand: expr, location: l)
        when :decrement
          advance; expr = AST::UnaryOp.new(op: :post_dec, operand: expr, location: l)
        else
          break
        end
      end

      expr
    end

    def parse_primary_expr
      l = loc
      case cur.type
      when :int_lit
        t = advance
        AST::IntLiteral.new(raw: t.value[:raw], suffix: t.value[:suffix], location: l)
      when :float_lit
        t = advance
        AST::FloatLiteral.new(raw: t.value[:raw], suffix: t.value[:suffix], location: l)
      when :string_lit
        # Adjacent string literal concatenation
        parts = []
        while cur?(:string_lit)
          t = advance
          parts << t.value[:value]
        end
        AST::StringLiteral.new(value: parts.join, prefix: nil, location: l)
      when :char_lit
        t = advance
        AST::CharLiteral.new(value: t.value[:value], prefix: t.value[:prefix], location: l)
      when :ident
        AST::Identifier.new(name: advance.value, location: l)
      when :lparen
        advance
        # Could be a parenthesised expression or compound literal
        expr = parse_expr
        expect(:rparen)
        expr
      when :kw__Generic
        parse_generic_selection
      else
        raise ParseError.new("unexpected token in expression: #{cur.type} ('#{cur.value}')", l)
      end
    end

    def parse_generic_selection
      l = loc; advance  # _Generic
      expect(:lparen)
      controlling = parse_assignment_expr
      expect(:comma)
      associations = []
      loop do
        if match(:kw_default)
          expect(:colon)
          associations << { type: :default, expr: parse_assignment_expr }
        else
          tn = parse_type_name
          expect(:colon)
          associations << { type: tn, expr: parse_assignment_expr }
        end
        break unless match(:comma)
      end
      expect(:rparen)
      { kind: :generic, controlling: controlling, associations: associations, location: l }
    end
  end
end
