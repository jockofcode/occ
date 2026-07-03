# frozen_string_literal: true

module OCC
  # Semantic analyser: walks the AST, resolves types, checks compatibility,
  # and annotates nodes with a :ctype attribute.
  class Semantic
    include Types

    def initialize
      @symbols      = SymbolTable.new
      @struct_tags  = {}    # tag => StructType
      @enum_tags    = {}    # tag => EnumType
      @typedef_map  = {}    # name => CType
      @current_func = nil   # return type of the function being analysed
      @errors       = []
      seed_builtins
    end

    attr_reader :errors

    def analyze(tu)
      tu.decls.each { |d| analyze_external(d) }
      tu
    end

    private

    # ── Error reporting ───────────────────────────────────────────────────────

    def err(msg, location = nil)
      @errors << SemanticError.new(msg, location)
      # Return a sentinel type so analysis can continue.
      Types::INT
    end

    # ── External declarations ─────────────────────────────────────────────────

    def analyze_external(node)
      case node
      when AST::FunctionDef
        analyze_function_def(node)
      when AST::Declaration
        analyze_declaration(node, global: true)
      when AST::StaticAssert
        check_static_assert(node)
      end
    end

    def analyze_function_def(fn)
      # resolve_type applies the full declarator including the function postfix,
      # so full_type IS a FunctionType.
      full_type = resolve_type(fn.specifiers, fn.return_type_fn)

      func_type = if full_type.is_a?(Types::FunctionType)
                    full_type
                  else
                    # Declarator had no function postfix – wrap manually.
                    pr = resolve_params(fn.params)
                    Types::FunctionType.new(full_type, pr[:params], variadic: pr[:variadic])
                  end

      ret_type = func_type.return_type
      fn.resolved_return_type = ret_type
      @symbols.define(fn.name, type: func_type, kind: :func, location: fn.location)

      @symbols.push_scope
      @current_func = ret_type

      func_type.params.each do |p|
        next unless p[:name]
        @symbols.define(p[:name], type: p[:type], kind: :var, location: fn.location)
      end

      analyze_stmt(fn.body)

      @current_func = nil
      @symbols.pop_scope
    end

    def analyze_declaration(decl, global: false)
      # Always process struct/union/enum definitions to register the type and
      # populate enumerator symbols, even when no declarators follow.
      build_base_type(decl.specifiers) if decl.specifiers.tag_decl

      decl.declarators.each do |d|
        base_type = resolve_type(decl.specifiers, d[:type_fn])

        # Infer array count from initializer list or string literal for unsized arrays
        if base_type.is_a?(Types::ArrayType) && base_type.count.nil?
          if d[:init].is_a?(Hash) && d[:init][:kind] == :initializer_list
            count = (d[:init][:items] || []).length
            base_type = Types::ArrayType.new(base_type.element, count) if count > 0
          elsif d[:init].is_a?(AST::StringLiteral)
            count = d[:init].value.length + 1
            base_type = Types::ArrayType.new(base_type.element, count)
          end
        end

        # Annotate the declarator hash so the IR builder can use the resolved type.
        d[:resolved_type] = base_type

        if decl.specifiers.storage == :typedef
          @typedef_map[d[:name]] = base_type
          @symbols.define(d[:name], type: base_type, kind: :typedef, location: decl.location)
          next
        end

        # Define the variable before analyzing its initializer so that
        # sizeof(*p) in p's own initializer resolves correctly (C99 §6.2.1:
        # scope begins after the declarator).
        @symbols.define(d[:name], type: base_type, kind: :var, location: decl.location)

        if d[:init]
          init_type = analyze_expr(d[:init])
          check_assignment_compat(base_type, init_type, decl.location) if d[:init].respond_to?(:ctype)
        end
      end
    end

    # ── _Generic selection ─────────────────────────────────────────────────────

    # Resolve a _Generic(controlling, T1: e1, T2: e2, default: ed) node.
    # Annotates node[:selected_expr] and returns its type.
    def resolve_generic(node)
      ct = analyze_expr(node[:controlling])
      ct_bare = ct.respond_to?(:unqualified) ? ct.unqualified : ct

      selected = nil
      default_assoc = nil

      node[:associations].each do |a|
        if a[:type] == :default
          default_assoc = a
          next
        end
        assoc_ct = begin
          spec = a[:type].is_a?(Hash) ? (a[:type][:specs] || a[:type]) : a[:type]
          base = build_base_type(spec) rescue nil
          next unless base
          type_fn = a[:type].is_a?(Hash) ? a[:type][:type_fn] : nil
          type_fn ? (type_fn.call(base) rescue base) : base
        rescue StandardError
          nil
        end
        next unless assoc_ct
        assoc_bare = assoc_ct.respond_to?(:unqualified) ? assoc_ct.unqualified : assoc_ct
        if ct_bare == assoc_bare
          selected = a
          break
        end
      end

      selected ||= default_assoc
      if selected
        node[:selected_expr] = selected[:expr]
        analyze_expr(selected[:expr])
      else
        Types::INT
      end
    rescue StandardError
      Types::INT
    end

    # ── _Static_assert ─────────────────────────────────────────────────────────

    def check_static_assert(node)
      val = eval_const_expr(node.expr)
      return if val.nil? || val != 0  # unknown or true — pass
      msg = node.message.is_a?(AST::StringLiteral) ? node.message.value : node.message.to_s
      loc = node.respond_to?(:location) ? node.location : nil
      raise SemanticError.new("static assertion failed: #{msg}", loc)
    end

    # Fold a constant expression to an integer, or nil if not foldable.
    def eval_const_expr(node)
      return nil unless node
      case node
      when AST::IntLiteral   then node.integer_value
      when AST::CharLiteral  then node.value.ord
      when AST::Identifier
        # enum constants are in the symbol table with kind: :enum_const
        sym = @symbols.lookup(node.name)
        sym && sym[:kind] == :enum_const ? sym[:value] : nil
      when AST::UnaryOp
        v = eval_const_expr(node.operand)
        return nil unless v
        case node.op
        when :unary_minus then -v
        when :logical_not then v == 0 ? 1 : 0
        when :bit_not     then ~v
        else nil
        end
      when AST::BinaryOp
        l = eval_const_expr(node.left)
        r = eval_const_expr(node.right)
        return nil unless l && r
        case node.op
        when :plus        then l + r
        when :minus       then l - r
        when :star        then l * r
        when :slash       then r != 0 ? l / r : nil
        when :percent     then r != 0 ? l % r : nil
        when :lshift      then l << r
        when :rshift      then l >> r
        when :amp         then l & r
        when :pipe        then l | r
        when :caret       then l ^ r
        when :eq          then l == r ? 1 : 0
        when :neq         then l != r ? 1 : 0
        when :lt          then l < r  ? 1 : 0
        when :leq         then l <= r ? 1 : 0
        when :gt          then l > r  ? 1 : 0
        when :geq         then l >= r ? 1 : 0
        when :logical_and then (l != 0 && r != 0) ? 1 : 0
        when :logical_or  then (l != 0 || r != 0) ? 1 : 0
        end
      when AST::TernaryOp
        c = eval_const_expr(node.cond)
        return nil if c.nil?
        c != 0 ? eval_const_expr(node.then_expr) : eval_const_expr(node.else_expr)
      when AST::Cast
        # For compile-time constant folding, evaluate inner expression.
        # Integer truncation edge cases don't matter for array sizes.
        eval_const_expr(node.expr)
      when AST::SizeofType
        node.sizeof_val || resolve_sizeof_type(node.type_spec)
      when AST::SizeofExpr
        node.sizeof_val
      else nil
      end
    rescue StandardError
      nil
    end

    # ── sizeof helpers ────────────────────────────────────────────────────────

    def sizeof_of_ctype(ct)
      return 8 unless ct
      u = ct.respond_to?(:unqualified) ? ct.unqualified : ct
      case u
      when Types::ArrayType
        return 8 if u.count.nil?  # unsized array — treat as pointer
        sizeof_of_ctype(u.element) * u.count
      when Types::PointerType, Types::FunctionType then 8
      else
        u.respond_to?(:size) ? u.size : 8
      end
    rescue StandardError
      8
    end

    def resolve_sizeof_type(spec)
      type_fn = spec.is_a?(Hash) ? spec[:type_fn] : nil
      spec = spec[:specs] if spec.is_a?(Hash) && spec[:specs]
      spec = spec[:specs] if spec.is_a?(Hash) && spec[:specs]
      base = build_base_type(spec) rescue Types::INT
      ct = type_fn ? (type_fn.call(base) rescue base) : base
      ct = convert_hash_type(ct) if ct.is_a?(Hash)
      sizeof_of_ctype(ct)
    rescue StandardError
      8
    end

    # ── Type resolution ───────────────────────────────────────────────────────

    def resolve_type(spec, type_fn)
      base = build_base_type(spec)
      result = type_fn ? type_fn.call(base) : base
      convert_hash_type(result)
    end

    def build_base_type(spec)
      if spec.typedef_name
        t = @typedef_map[spec.typedef_name]
        return t || err("unknown typedef '#{spec.typedef_name}'")
      end

      if spec.tag_decl.is_a?(AST::StructSpec)
        return define_struct(spec.tag_decl)
      end
      if spec.tag_decl.is_a?(AST::EnumSpec)
        return define_enum(spec.tag_decl)
      end

      Types.from_specifiers(spec)
    end

    # Convert the hash-form type (produced by Parser's type_fn) to a CType.
    def convert_hash_type(type)
      return type if type.is_a?(Types::CType)
      return Types::INT unless type.is_a?(Hash)

      case type[:kind]
      when :pointer
        base = convert_hash_type(type[:base])
        Types::PointerType.new(base, type[:qualifiers] || [])
      when :array
        elem = convert_hash_type(type[:element])
        count = if type[:size].is_a?(AST::IntLiteral)
                  type[:size].integer_value
                elsif type[:size]
                  eval_const_expr(type[:size])
                end
        Types::ArrayType.new(elem, count)
      when :function
        ret   = convert_hash_type(type[:return])
        params = resolve_params(type[:params])
        Types::FunctionType.new(ret, params[:params], variadic: params[:variadic])
      else
        Types::INT
      end
    end

    def resolve_params(params_hash)
      return { params: [], variadic: false } unless params_hash

      resolved = params_hash[:params].map do |p|
        t = resolve_type(p[:specs], p[:type_fn])
        # Array params decay to pointers
        t = Types::PointerType.new(t.element) if t.is_a?(Types::ArrayType)
        # Annotate the original param hash so the IR builder can use the
        # resolved type without re-running declarator resolution.
        p[:resolved_type] = t if p.is_a?(Hash)
        { name: p[:name], type: t }
      end

      { params: resolved, variadic: params_hash[:variadic] }
    end

    def define_struct(spec)
      tag  = spec.tag
      kind = spec.keyword

      existing = tag ? @struct_tags[tag] : nil
      st = existing || Types::StructType.new(kind, tag)
      @struct_tags[tag] = st if tag

      if spec.fields
        offset     = 0      # current byte offset within struct
        bit_offset = 0      # current bit offset within the current storage unit
        unit_size  = 0      # byte size of the current storage unit (0 = not in a bitfield run)

        fields = spec.fields.flat_map do |field_decl|
          if field_decl.declarators.empty?
            # ── Anonymous struct/union member (C11 §6.7.2.1 para 13) ────────
            ft = (resolve_type(field_decl.specifiers, nil) rescue nil)
            next [] unless ft.is_a?(Types::StructType) && ft.complete?
            # Flush any open bitfield storage unit
            if kind == :kw_struct && unit_size > 0
              offset += unit_size if bit_offset > 0
              bit_offset = 0
              unit_size  = 0
            end
            base_off = kind == :kw_struct ? align_up(offset, ft.align) : 0
            inlined = ft.fields.map do |f|
              { name: f[:name], type: f[:type],
                offset: base_off + f[:offset],
                bit_offset: f[:bit_offset], bit_width: f[:bit_width], unit_size: f[:unit_size] }
            end
            offset = base_off + ft.size if kind == :kw_struct
            inlined
          else
            field_decl.declarators.filter_map do |d|
              ft = resolve_type(field_decl.specifiers, d[:type_fn]) rescue Types::INT

              if d[:bitwidth]
                # ── Bitfield member ─────────────────────────────────────────────
                width = case d[:bitwidth]
                        when AST::IntLiteral then d[:bitwidth].integer_value
                        else 1
                        end
                ft_size = (ft.size rescue 4).clamp(1, 8)

                # width == 0: anonymous zero-width field forces alignment
                if width == 0
                  if kind == :kw_struct && bit_offset > 0
                    offset   += unit_size
                    bit_offset = 0
                    unit_size  = 0
                  end
                  next nil
                end

                # Start a new storage unit if needed
                if unit_size == 0 || bit_offset + width > unit_size * 8
                  if kind == :kw_struct && unit_size > 0 && bit_offset > 0
                    offset += unit_size
                  end
                  if kind == :kw_struct
                    offset    = align_up(offset, ft_size)
                  end
                  bit_offset = 0
                  unit_size  = ft_size
                end

                f = d[:name] ? {
                  name:       d[:name],
                  type:       ft,
                  offset:     offset,
                  bit_offset: bit_offset,
                  bit_width:  width,
                  unit_size:  unit_size
                } : nil
                bit_offset += width
                f
              else
                # ── Regular member ───────────────────────────────────────────────
                # Flush any open bitfield storage unit
                if kind == :kw_struct && unit_size > 0
                  offset    += unit_size if bit_offset > 0
                  bit_offset = 0
                  unit_size  = 0
                end
                offset = align_up(offset, ft.align) if kind == :kw_struct
                f = d[:name] ? { name: d[:name], type: ft, offset: offset,
                                 bit_offset: nil, bit_width: nil, unit_size: nil } : nil
                offset += (ft.size rescue 4) if kind == :kw_struct
                f
              end
            end
          end
        end
        st.fields = fields.compact
      end

      st
    end

    def define_enum(spec)
      tag = spec.tag
      et = tag ? (@enum_tags[tag] ||= Types::EnumType.new(tag)) : Types::EnumType.new(nil)
      @enum_tags[tag] = et if tag

      if spec.enumerators
        val = 0
        et.enumerators = {}
        spec.enumerators.each do |e|
          explicit = e.value ? (eval_const_expr(e.value) || (e.value.is_a?(AST::IntLiteral) ? e.value.integer_value : nil)) : nil
          val = explicit || val
          et.enumerators[e.name] = val
          @symbols.define(e.name, type: Types::INT, kind: :enum_const, value: val, location: e.location)
          val += 1
        end
      end

      et
    end

    # ── Statement analysis ────────────────────────────────────────────────────

    def analyze_stmt(node)
      case node
      when AST::CompoundStmt
        @symbols.push_scope
        node.items.each { |item| analyze_block_item(item) }
        @symbols.pop_scope
      when AST::ExprStmt
        analyze_expr(node.expr) if node.expr
      when AST::ReturnStmt
        if node.value
          vt = analyze_expr(node.value)
          check_assignment_compat(@current_func, vt, node.location) if @current_func
        elsif @current_func && !@current_func.void?
          err("return with no value in non-void function", node.location)
        end
      when AST::IfStmt
        analyze_expr(node.cond)
        analyze_stmt(node.then_body)
        analyze_stmt(node.else_body) if node.else_body
      when AST::WhileStmt, AST::DoWhileStmt
        analyze_expr(node.cond)
        analyze_stmt(node.body)
      when AST::ForStmt
        @symbols.push_scope
        analyze_block_item(node.init) if node.init
        analyze_expr(node.cond) if node.cond
        analyze_expr(node.update) if node.update
        analyze_stmt(node.body)
        @symbols.pop_scope
      when AST::SwitchStmt
        analyze_expr(node.expr)
        analyze_stmt(node.body)
      when AST::CaseStmt, AST::DefaultStmt
        analyze_stmt(node.stmt)
      when AST::LabelStmt
        analyze_stmt(node.stmt)
      when AST::BreakStmt, AST::ContinueStmt, AST::GotoStmt
        nil  # no-op
      when AST::StaticAssert
        check_static_assert(node)
      else
        # silently ignore unknown statement types
      end
    end

    def analyze_block_item(item)
      case item
      when AST::Declaration then analyze_declaration(item)
      when AST::StaticAssert then check_static_assert(item)
      else analyze_stmt(item)
      end
    end

    # ── Expression analysis ────────────────────────────────────────────────────
    # Returns the CType of the expression.

    def analyze_expr(node)
      return Types::INT unless node
      # Hash nodes — only _Generic selections are meaningful here.
      if node.is_a?(Hash)
        return resolve_generic(node) if node[:kind] == :generic
        return Types::INT
      end

      ctype = case node
              when AST::IntLiteral    then type_of_int_literal(node)
              when AST::FloatLiteral  then type_of_float_literal(node)
              when AST::StringLiteral then Types::PointerType.new(Types::CHAR)
              when AST::CharLiteral   then Types::INT
              when AST::Identifier    then type_of_identifier(node)
              when AST::BinaryOp      then type_of_binop(node)
              when AST::UnaryOp       then type_of_unary(node)
              when AST::Assign        then type_of_assign(node)
              when AST::TernaryOp     then type_of_ternary(node)
              when AST::Cast          then type_of_cast(node)
              when AST::CallExpr      then type_of_call(node)
              when AST::IndexExpr     then type_of_index(node)
              when AST::MemberExpr    then type_of_member(node)
              when AST::SizeofType
                node.sizeof_val = resolve_sizeof_type(node.type_spec)
                Types::ULONG
              when AST::SizeofExpr
                node.sizeof_val = if node.operand.is_a?(AST::StringLiteral)
                                    node.operand.value.length + 1
                                  else
                                    ot = analyze_expr(node.operand) rescue Types::INT
                                    sizeof_of_ctype(ot)
                                  end
                Types::ULONG
              when AST::AlignofType then Types::ULONG
              when AST::CommaExpr
                node.exprs.map { |e| analyze_expr(e) }.last
              else
                Types::INT
              end
      node.ctype = ctype if node.respond_to?(:ctype=)
      ctype
    end

    def type_of_int_literal(node)
      suffix = node.suffix.downcase
      if suffix.include?('ull') || suffix.include?('llu')
        Types::ULONGLONG
      elsif suffix.include?('ll')
        Types::LONGLONG
      elsif suffix.include?('ul') || suffix.include?('lu')
        Types::ULONG
      elsif suffix.include?('u')
        Types::UINT
      elsif suffix.include?('l')
        Types::LONG
      else
        Types::INT
      end
    end

    def type_of_float_literal(node)
      suffix = node.suffix.downcase
      suffix == 'f' ? Types::FLOAT : suffix == 'l' ? Types::LONGDOUBLE : Types::DOUBLE
    end

    def type_of_identifier(node)
      sym = @symbols.lookup(node.name)
      unless sym
        err("undeclared identifier '#{node.name}'", node.location)
        return Types::INT
      end
      sym.type
    end

    def type_of_binop(node)
      lt = analyze_expr(node.left)
      rt = analyze_expr(node.right)

      case node.op
      when :eq, :neq, :lt, :gt, :leq, :geq, :logical_and, :logical_or
        Types::INT
      when :plus, :minus
        lu = lt.respond_to?(:unqualified) ? lt.unqualified : lt
        ru = rt.respond_to?(:unqualified) ? rt.unqualified : rt
        if lu.is_a?(Types::PointerType)
          ru.is_a?(Types::PointerType) && node.op == :minus ? Types::LONG : lu
        elsif lu.is_a?(Types::ArrayType)
          Types::PointerType.new(lu.element)
        elsif ru.is_a?(Types::PointerType) || ru.is_a?(Types::ArrayType)
          ru.is_a?(Types::ArrayType) ? Types::PointerType.new(ru.element) : ru
        else
          Types.usual_arithmetic_conversion(lu, ru)
        end
      else
        lu = lt.respond_to?(:unqualified) ? lt.unqualified : lt
        ru = rt.respond_to?(:unqualified) ? rt.unqualified : rt
        Types.usual_arithmetic_conversion(lu, ru)
      end
    end

    def type_of_unary(node)
      t = analyze_expr(node.operand)
      case node.op
      when :addr_of   then Types::PointerType.new(t)
      when :deref
        if t.is_a?(Types::PointerType) || t.is_a?(Types::ArrayType)
          t.respond_to?(:base) ? t.base : t.element
        else
          err("cannot dereference non-pointer type", node.location)
        end
      when :logical_not then Types::INT
      when :post_inc, :post_dec, :pre_inc, :pre_dec then t
      else
        Types.integer_promote(t)
      end
    end

    def type_of_assign(node)
      lt = analyze_expr(node.target)
      rt = analyze_expr(node.value)
      # For compound pointer arithmetic (p += n, p -= n), the rhs is an integer
      # being added to/subtracted from a pointer — the result type is the pointer
      # type so no assignment-compat check is needed.
      lt_inner = lt.respond_to?(:unqualified) ? lt.unqualified : lt
      rt_inner = rt.respond_to?(:unqualified) ? rt.unqualified : rt
      pointer_arith = lt_inner.is_a?(Types::PointerType) &&
                      rt_inner.respond_to?(:integer?) && rt_inner.integer? &&
                      %i[plus_assign minus_assign].include?(node.op)
      check_assignment_compat(lt, rt, node.location) unless pointer_arith
      lt
    end

    def type_of_ternary(node)
      analyze_expr(node.cond)
      tt = analyze_expr(node.then_expr)
      et = analyze_expr(node.else_expr)
      Types.usual_arithmetic_conversion(tt.unqualified, et.unqualified)
    rescue StandardError
      tt
    end

    def type_of_cast(node)
      analyze_expr(node.expr)
      # The cast type spec in the AST is a hash {specs:, type_fn:}
      if node.type_spec.is_a?(Hash)
        resolve_type(node.type_spec[:specs], node.type_spec[:type_fn])
      else
        Types::INT
      end
    end

    def type_of_call(node)
      ft = analyze_expr(node.callee)
      # Decay pointer-to-function to function
      ft = ft.base if ft.is_a?(Types::PointerType) && ft.base.is_a?(Types::FunctionType)
      node.args.each { |a| analyze_expr(a) }

      if ft.is_a?(Types::FunctionType)
        unless ft.variadic || ft.params.length == node.args.length || ft.params.empty?
          err("wrong number of arguments to function", node.location)
        end
        ft.return_type
      else
        Types::INT   # unknown function – be permissive
      end
    end

    def type_of_index(node)
      at = analyze_expr(node.array)
      analyze_expr(node.index)
      if at.is_a?(Types::ArrayType)
        at.element
      elsif at.is_a?(Types::PointerType)
        at.base
      else
        err("subscript of non-array/pointer", node.location)
      end
    end

    def type_of_member(node)
      t = analyze_expr(node.expr)
      t = t.base if node.arrow && t.is_a?(Types::PointerType)
      t = t.unqualified if t.respond_to?(:unqualified)
      if t.is_a?(Types::StructType) && t.complete?
        field = t.fields.find { |f| f[:name] == node.member }
        return field ? field[:type] : err("no field '#{node.member}' in #{t}", node.location)
      end
      err("member access on non-struct/union", node.location)
    end

    # ── Assignment compatibility ───────────────────────────────────────────────

    def check_assignment_compat(ltype, rtype, loc)
      lt = ltype.unqualified
      rt = rtype.unqualified

      return if lt == rt
      return if lt.arithmetic? && rt.arithmetic?
      return if lt.is_a?(Types::PointerType) && rt.is_a?(Types::PointerType)
      return if lt.is_a?(Types::PointerType) && rt == Types::INT   # null pointer constant
      return if lt.integer? && rt.is_a?(Types::PointerType)
      # void* is compatible with any pointer type (C standard)
      return if lt.is_a?(Types::PointerType) && rt.is_a?(Types::VoidType)
      return if lt.is_a?(Types::VoidType) && rt.is_a?(Types::PointerType)
      # function designator decays to function pointer; allow assigning to any pointer
      return if lt.is_a?(Types::PointerType) && rt.is_a?(Types::FunctionType)
      # array decays to pointer in assignment context
      return if lt.is_a?(Types::PointerType) && rt.is_a?(Types::ArrayType)
      # char array initialized from string literal (char[] = "...")
      return if lt.is_a?(Types::ArrayType) && rt.is_a?(Types::PointerType)
      # array-to-array (struct copy of same-type arrays)
      return if lt.is_a?(Types::ArrayType) && rt.is_a?(Types::ArrayType)

      err("incompatible types in assignment: #{lt} and #{rt}", loc)
    end

    # ── Struct alignment ───────────────────────────────────────────────────────

    def align_up(offset, align)
      return offset if align.zero?
      (offset + align - 1) / align * align
    end

    # ── Builtins ──────────────────────────────────────────────────────────────

    def seed_builtins
      # Commonly-used libc functions so they don't produce undeclared errors
      printf_type = Types::FunctionType.new(
        Types::INT,
        [{ name: 'fmt', type: Types::PointerType.new(Types::CHAR) }],
        variadic: true
      )
      @symbols.define('printf',  type: printf_type, kind: :func)
      @symbols.define('fprintf', type: printf_type, kind: :func)
      @symbols.define('puts',    type: Types::FunctionType.new(Types::INT, [{ name: 's', type: Types::PointerType.new(Types::CHAR) }]), kind: :func)
      @symbols.define('malloc',  type: Types::FunctionType.new(Types::PointerType.new(Types::VOID), [{ name: 'sz', type: Types::ULONG }]), kind: :func)
      @symbols.define('free',    type: Types::FunctionType.new(Types::VOID, [{ name: 'p', type: Types::PointerType.new(Types::VOID) }]), kind: :func)
      @symbols.define('exit',    type: Types::FunctionType.new(Types::VOID, [{ name: 'c', type: Types::INT }]), kind: :func)
    end
  end
end
