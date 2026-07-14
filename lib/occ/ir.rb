# frozen_string_literal: true

module OCC
  module IR
    # ── Instructions ───────────────────────────────────────────────────────────

    # An operand is either a Temp, a Const, or a GlobalRef.
    Temp      = Struct.new(:id)    { def to_s = "%#{id}" }
    Const     = Struct.new(:value) { def to_s = value.to_s }
    GlobalRef = Struct.new(:name)  { def to_s = "@#{name}" }
    StringRef = Struct.new(:id)    { def to_s = "str_#{id}" }
    LabelRef  = Struct.new(:func, :label) { def to_s = "&&#{func}:#{label}" }

    # All instructions carry an optional type annotation.
    class Instruction
      attr_reader :type
      def initialize(type = nil) = @type = type
    end

    # dst = src
    class Copy < Instruction
      attr_reader :dst, :src
      def initialize(dst, src, type = nil) = (super(type); @dst = dst; @src = src)
      def to_s = "#{@dst} = copy #{@src}"
    end

    # dst = op src  (unary)
    class Unary < Instruction
      attr_reader :dst, :op, :src
      def initialize(dst, op, src, type = nil) = (super(type); @dst = dst; @op = op; @src = src)
      def to_s = "#{@dst} = #{@op} #{@src}"
    end

    # dst = left op right  (binary)
    class Binary < Instruction
      attr_reader :dst, :op, :left, :right
      def initialize(dst, op, left, right, type = nil)
        super(type); @dst = dst; @op = op; @left = left; @right = right
      end
      def to_s = "#{@dst} = #{@op} #{@left}, #{@right}"
    end

    # dst = load ptr
    class Load < Instruction
      attr_reader :dst, :ptr, :elem_size
      def initialize(dst, ptr, type = nil, elem_size = 8)
        super(type); @dst = dst; @ptr = ptr; @elem_size = elem_size
      end
      def to_s = "#{@dst} = load#{@elem_size != 8 ? ".#{@elem_size}" : ''} #{@ptr}"
    end

    # store value → ptr
    class Store < Instruction
      attr_reader :ptr, :value, :elem_size
      def initialize(ptr, value, type = nil, elem_size = 8)
        super(type); @ptr = ptr; @value = value; @elem_size = elem_size
      end
      def to_s = "store#{@elem_size != 8 ? ".#{@elem_size}" : ''} #{@value} → #{@ptr}"
    end

    # dst = alloca  (allocate local stack slot)
    class Alloca < Instruction
      attr_reader :dst, :ctype
      def initialize(dst, ctype) = (@dst = dst; @ctype = ctype)
      def to_s = "#{@dst} = alloca #{@ctype}"
    end

    # dst = addr_of variable
    class AddrOf < Instruction
      attr_reader :dst, :src
      def initialize(dst, src, type = nil) = (super(type); @dst = dst; @src = src)
      def to_s = "#{@dst} = addr_of #{@src}"
    end

    # dst = current stack pointer
    class StackPointer < Instruction
      attr_reader :dst
      def initialize(dst) = (@dst = dst)
      def to_s = "#{@dst} = stack_pointer"
    end

    # dst = gep ptr, index  (get element pointer)
    class Gep < Instruction
      attr_reader :dst, :ptr, :index, :elem_size
      def initialize(dst, ptr, index, elem_size = 8, type = nil)
        super(type); @dst = dst; @ptr = ptr; @index = index; @elem_size = elem_size
      end
      def to_s = "#{@dst} = gep #{@ptr}, #{@index} stride #{@elem_size}"
    end

    # dst = call func(args...)
    class Call < Instruction
      attr_reader :dst, :func, :args
      def initialize(dst, func, args, type = nil)
        super(type); @dst = dst; @func = func; @args = args
      end
      def to_s = "#{@dst} = call #{@func}(#{@args.join(', ')})"
    end

    # jmp label
    class Jump < Instruction
      attr_reader :target
      def initialize(target) = (@target = target)
      def to_s = "jmp #{@target}"
    end

    # indirect jump through an address-valued expression (GNU computed goto)
    class IndirectJump < Instruction
      attr_reader :target
      def initialize(target) = (@target = target)
      def to_s = "ijmp #{@target}"
    end

    # cjmp cond, true_label, false_label
    class CondJump < Instruction
      attr_reader :cond, :true_label, :false_label
      def initialize(cond, true_label, false_label)
        @cond = cond; @true_label = true_label; @false_label = false_label
      end
      def to_s = "cjmp #{@cond}, #{@true_label}, #{@false_label}"
    end

    # ret [value]
    class Return < Instruction
      attr_reader :value
      def initialize(value = nil) = (@value = value)
      def to_s = value ? "ret #{@value}" : 'ret'
    end

    # dst = cast src to type_name
    class Cast < Instruction
      attr_reader :dst, :src, :to_type
      def initialize(dst, src, to_type, type = nil)
        super(type); @dst = dst; @src = src; @to_type = to_type
      end
      def to_s = "#{@dst} = cast #{@src} to #{@to_type}"
    end

    # ── Basic block ────────────────────────────────────────────────────────────

    class BasicBlock
      attr_reader :label, :instrs
      attr_accessor :preds, :succs

      def initialize(label)
        @label  = label
        @instrs = []
        @preds  = []
        @succs  = []
      end

      def <<(instr) = @instrs << instr
      def terminated? = @instrs.last.is_a?(Jump) || @instrs.last.is_a?(IndirectJump) || @instrs.last.is_a?(CondJump) || @instrs.last.is_a?(Return)

      def to_s
        lines = ["#{@label}:"]
        @instrs.each { |i| lines << "  #{i}" }
        lines.join("\n")
      end
    end

    # ── Function ───────────────────────────────────────────────────────────────

    class Function
      attr_reader :name, :params, :blocks, :return_type
      attr_accessor :variadic, :static, :constructor

      def initialize(name, params, return_type, variadic: false, static: false, constructor: false)
        @name        = name
        @params      = params   # [{name:, type:}]
        @return_type = return_type
        @variadic    = variadic
        @static      = static
        @constructor = constructor
        @blocks      = []
      end

      def entry_block = @blocks.first
      def add_block(b) = @blocks << b

      def to_s
        sig = "#{@return_type} #{@name}(#{@params.map { |p| "#{p[:type]} #{p[:name]}" }.join(', ')})"
        "function #{sig} {\n#{@blocks.map(&:to_s).join("\n")}\n}"
      end
    end

    # ── Module ────────────────────────────────────────────────────────────────

    class Mod
      attr_reader :functions, :globals, :tls_globals, :strings, :variadic_funcs, :fp_funcs,
                  :func_names, :defined_funcs, :static_funcs

      def initialize
        @functions     = []
        @globals       = {}         # name => {type:, init:}
        @tls_globals   = {}         # name => {type:, init:}  (_Thread_local variables)
        @strings       = []         # StringRef values
        @variadic_funcs = {}        # name => named_param_count
        @fp_funcs       = Set.new   # names of functions returning float/double
        @func_names     = Set.new   # all known function names (defined or declared extern)
        @defined_funcs  = Set.new   # functions with a body in this translation unit
        @static_funcs   = Set.new   # functions declared static (internal linkage)
      end

      def add_function(f)
        @functions << f
        @func_names << f.name
        @defined_funcs << f.name
      end
      def add_global(name, type, init = nil, static: false) = (@globals[name] = { type: type, init: init, static: static })
      def add_tls_global(name, type) = (@tls_globals[name] = { type: type })
      def add_string(value) = StringRef.new(@strings.tap { @strings << value }.length - 1)
      def mark_variadic(name, named_count = 0) = (@variadic_funcs[name] = named_count)
      def mark_fp_func(name)    = @fp_funcs << name
      def mark_func(name)       = @func_names << name
      def mark_static_func(name) = @static_funcs << name

      def to_s
        parts = []
        @strings.each_with_index { |s, i| parts << "str_#{i} = #{s.inspect}" }
        @globals.each { |n, g| parts << "global #{g[:type]} #{n}" }
        @functions.each { |f| parts << f.to_s }
        parts.join("\n\n")
      end
    end

    # ── IR Builder ────────────────────────────────────────────────────────────
    #
    # Walks the AST and emits IR instructions.

    class Builder
      def initialize
        @mod             = Mod.new
        @func            = nil     # current Function
        @block           = nil     # current BasicBlock
        @temp_counter    = 0
        @label_counter   = 0
        @locals          = {}      # name => Alloca temp
        @local_ctypes    = {}      # name => CType (for array decay when node.ctype is nil)
        @static_locals   = {}      # name => mangled global name (static-storage locals)
        @break_target         = nil
        @cont_target          = nil
        @switch_case_map      = nil  # current switch's case_map (for nested case labels)
        @switch_default_block = nil  # current switch's default block
        @enum_constants       = {}   # name => Integer (compile-time enum values)
        @func_ast_defs        = {}   # name => AST::FunctionDef (for const-folding inline calls)
      end

      def build(tu)
        tu.decls.each { |d| build_external(d) }
        @mod
      end

      attr_reader :mod

      private

      # ── Helpers ─────────────────────────────────────────────────────────────

      def new_temp
        t = Temp.new(@temp_counter)
        @temp_counter += 1
        t
      end

      def new_label(hint = 'L')
        l = "#{hint}#{@label_counter}"
        @label_counter += 1
        l
      end

      def new_block(label = new_label)
        bb = BasicBlock.new(label)
        @func&.add_block(bb)
        bb
      end

      def emit(instr)
        @block << instr unless @block.terminated?
        instr
      end

      def switch_to(block)
        @block = block
      end

      def jump_to(block)
        emit(Jump.new(block.label)) unless @block&.terminated?
        switch_to(block)
      end

      def with_local_scope
        saved_locals = @locals
        saved_local_ctypes = @local_ctypes
        saved_static_locals = @static_locals
        @locals = @locals.dup
        @local_ctypes = @local_ctypes.dup
        @static_locals = @static_locals.dup
        yield
      ensure
        @locals = saved_locals
        @local_ctypes = saved_local_ctypes
        @static_locals = saved_static_locals
      end

      # ── External declarations ────────────────────────────────────────────────

      def build_external(node)
        case node
        when AST::FunctionDef  then build_function(node)
        when AST::Declaration  then build_global_decl(node)
        end
      end

      def build_function(fn)
        @func_ast_defs[fn.name] = fn   # store for compile-time constant folding in case labels
        @temp_counter        = 0
        @label_counter       = 0
        @locals              = {}
        @local_ctypes        = {}
        @static_locals       = {}
        @static_local_counts = {}   # base_mangled => count, for uniquifying same-named statics in different scopes
        @func_ret_ctype  = fn.respond_to?(:resolved_return_type) ? fn.resolved_return_type : nil

        ret_type = fn.specifiers.type_keywords.first&.to_s || 'int'

        # Build logical parameter list with resolved CTypes (annotated by the
        # semantic analyser) so struct-by-value params can be sized correctly.
        ast_params = (fn.params || { params: [] })[:params]
        variadic   = (fn.params || { variadic: false })[:variadic]
        logical    = ast_params.map do |p|
          ct       = p[:resolved_type]
          type_str = p[:specs]&.type_keywords&.first&.to_s || 'int'
          { name: p[:name], ctype: ct, type: type_str, nregs: param_reg_slots(ct) }
        end

        # Flat parameter list — one entry per incoming register slot. Multi-slot
        # struct params get placeholder entries for their additional registers so
        # the codegen prologue saves each one.
        flat_params = []
        logical.each do |lp|
          lp[:nregs].times do |i|
            flat_params << if i.zero?
                             { name: lp[:name], type: lp[:ctype] || lp[:type] }
                           else
                             { name: nil, type: 'long' }
                           end
          end
        end

        is_static = fn.specifiers.storage == :static || @mod.static_funcs.include?(fn.name)
        is_ctor   = fn.respond_to?(:constructor) && fn.constructor
        @func = Function.new(fn.name, flat_params, ret_type, variadic: variadic, static: is_static, constructor: is_ctor)
        @mod.add_function(@func)
        @mod.mark_variadic(fn.name, flat_params.length) if variadic
        resolved_ret = fn.respond_to?(:resolved_return_type) && fn.resolved_return_type
        is_fp_ret = if resolved_ret
                      resolved_ret.is_a?(OCC::Types::FloatingType) ||
                        (resolved_ret.respond_to?(:unqualified) && resolved_ret.unqualified.is_a?(OCC::Types::FloatingType))
                    else
                      ret_type =~ /\A(float|double|long double)\z/
                    end
        @mod.mark_fp_func(fn.name) if is_fp_ret

        entry = new_block('entry')
        switch_to(entry)

        # Phase 1: capture all incoming register values into copy temps FIRST so
        # that later alloca/store work does not overwrite a register slot before
        # all registers have been read.
        reg_idx = 0
        param_copies = logical.map do |lp|
          unless lp[:name]
            reg_idx += lp[:nregs]
            next nil
          end
          cts = (0...lp[:nregs]).map do
            ct = new_temp
            emit(Copy.new(ct, Temp.new(reg_idx)))
            reg_idx += 1
            ct
          end
          [lp, cts]
        end.compact

        # Phase 2: alloca + store for each parameter. Multi-register struct
        # params store consecutive 8-byte halves into a single struct-sized slot.
        param_copies.each do |(lp, cts)|
          slot = new_temp
          alloca_ct = lp[:ctype] || lp[:type]
          emit(Alloca.new(slot, alloca_ct))
          if cts.length == 1
            struct_sz = alloca_ct.is_a?(OCC::Types::StructType) && alloca_ct.complete? ? (alloca_ct.size rescue 0) : 0
            if struct_sz > 16
              # Large struct passed indirectly via pointer in a single register.
              # Copy the struct bytes from the incoming pointer into our alloca slot.
              base_addr = new_temp
              emit(AddrOf.new(base_addr, slot))
              emit(Store.new(base_addr, cts.first, alloca_ct, struct_sz))
            else
              emit(Store.new(slot, cts.first))
            end
          else
            base_addr = new_temp
            emit(AddrOf.new(base_addr, slot))
            cts.each_with_index do |ct, i|
              if i.zero?
                emit(Store.new(slot, ct))
              else
                gep = new_temp
                emit(Gep.new(gep, base_addr, Const.new(i), 8))
                emit(Store.new(gep, ct))
              end
            end
          end
          @locals[lp[:name]] = slot
          @local_ctypes[lp[:name]] = lp[:ctype] if lp[:ctype]
        end

        build_stmt(fn.body)

        # Ensure all blocks are terminated
        emit(Return.new) unless @block.terminated?

        @func = nil
      end

      # Number of incoming integer registers a parameter of the given ctype
      # consumes under the AArch64 procedure call standard. Composite types up
      # to 16 bytes pack into 2 consecutive registers; everything else uses one.
      def param_reg_slots(ctype)
        return 1 unless ctype.is_a?(OCC::Types::StructType) && ctype.complete?
        sz = (ctype.size rescue 0)
        sz > 8 && sz <= 16 ? 2 : 1
      end

      def collect_enum_constants(tag_decl)
        if tag_decl.is_a?(AST::EnumSpec) && tag_decl.enumerators
          val = 0
          tag_decl.enumerators.each do |e|
            if e.value
              ev = eval_const_init(e.value)
              val = ev if ev
            end
            @enum_constants[e.name] = val
            val += 1
          end
        elsif tag_decl.is_a?(AST::StructSpec) && tag_decl.fields
          tag_decl.fields.each do |field_decl|
            collect_enum_constants(field_decl.specifiers.tag_decl) if field_decl.specifiers.tag_decl
          end
        end
      end

      def build_global_decl(decl)
        # Collect enum constants from inline enum/struct definitions (including nested enums in structs).
        collect_enum_constants(decl.specifiers.tag_decl) if decl.specifiers.tag_decl

        # Typedef declarations define types, not variables — nothing to emit.
        return if decl.specifiers.storage == :typedef

        # Register variadic and FP-returning extern declarations before skipping them.
        if decl.specifiers.storage == :extern
          base = begin
            OCC::Types.from_specifiers(decl.specifiers)
          rescue StandardError
            OCC::Types::INT
          end

          decl.declarators.each do |d|
            full_type = d[:type_fn]&.call(base) rescue nil
            next unless full_type.is_a?(Hash) && full_type[:kind] == :function

            params = full_type[:params]
            if params.is_a?(Hash) && params[:variadic]
              named_count = params[:params]&.length || 0
              @mod.mark_variadic(d[:name], named_count)
            end

            ret = full_type[:return]
            @mod.mark_fp_func(d[:name]) if ret.is_a?(OCC::Types::FloatingType)
            @mod.mark_func(d[:name])
          end
          return
        end

        base_type = begin
          OCC::Types.from_specifiers(decl.specifiers)
        rescue StandardError
          OCC::Types::INT
        end

        decl.declarators.each do |d|
          # Skip function declarations (no body — these are prototypes).
          # But register them in func_names so the codegen emits correct function-address
          # code (not data-load code) when these names appear in expressions.
          type_sample = d[:type_fn]&.call(:base)
          resolved = d[:resolved_type]
          resolved_bare = resolved.respond_to?(:unqualified) ? resolved.unqualified : resolved
          is_func_decl = (type_sample.is_a?(Hash) && type_sample[:kind] == :function) ||
                         resolved_bare.is_a?(OCC::Types::FunctionType)
          if is_func_decl
            full_type = d[:type_fn]&.call(base_type) rescue nil
            if full_type.is_a?(Hash) && full_type[:kind] == :function
              params = full_type[:params]
              if params.is_a?(Hash) && params[:variadic]
                named_count = params[:params]&.length || 0
                @mod.mark_variadic(d[:name], named_count)
              end
              ret = full_type[:return]
              @mod.mark_fp_func(d[:name]) if ret.is_a?(OCC::Types::FloatingType)
            elsif resolved_bare.is_a?(OCC::Types::FunctionType)
              ft = resolved_bare
              @mod.mark_variadic(d[:name], ft.params.length) if ft.variadic
              @mod.mark_fp_func(d[:name]) if ft.return_type.is_a?(OCC::Types::FloatingType)
            end
            @mod.mark_func(d[:name])
            @mod.mark_static_func(d[:name]) if decl.specifiers.storage == :static
            next
          end

          # Prefer the type resolved by the semantic analyser (handles typedefs, etc.)
          actual_type = d[:resolved_type] || begin
            d[:type_fn]&.call(base_type) || base_type
          rescue StandardError
            'int'
          end
          # Discard function-type results (shouldn't happen here, but be safe)
          actual_type = 'int' if actual_type.is_a?(Hash)
          actual_type = 'int' if actual_type.is_a?(OCC::Types::FunctionType)

          if decl.specifiers.storage == :_Thread_local
            @mod.add_tls_global(d[:name], actual_type)
          else
            init_val = d[:init] ? eval_const_init(d[:init], allow_ref: true) : nil
            is_static_global = decl.specifiers.storage == :static
            @mod.add_global(d[:name], actual_type, init_val, static: is_static_global)
          end
        end
      end

      # Evaluate a simple constant initializer.
      # Returns Integer, Float, { kind: :string, value: "..." }, { kind: :ref, name: "..." },
      # { kind: :label_ref, func: "...", label: "..." },
      # or { kind: :initializer_list, items: [...] } for compound initializers.
      # Sign-extend a char literal byte value, matching signed-char platforms.
      def char_lit_int(str)
        v = str.ord
        v > 127 ? v - 256 : v
      end

      def eval_const_init(expr, allow_ref: false)
        case expr
        when AST::IntLiteral   then expr.integer_value
        when AST::CharLiteral  then char_lit_int(expr.value)
        when AST::FloatLiteral then expr.raw.to_f
        when AST::StringLiteral
          { kind: :string, value: expr.value }
        when AST::LabelAddr
          { kind: :label_ref, func: @func&.name, label: expr.name } if allow_ref && @func
        when AST::SizeofType
          expr.sizeof_val
        when AST::SizeofExpr
          expr.sizeof_val
        when AST::BuiltinOffsetof
          expr.sizeof_val
        when AST::Identifier
          if @enum_constants.key?(expr.name)
            @enum_constants[expr.name]
          elsif allow_ref
            { kind: :ref, name: expr.name }
          end
        when AST::Cast
          eval_const_init(expr.expr, allow_ref: allow_ref)
        when AST::UnaryOp
          if expr.op == :addr_of && allow_ref
            operand = expr.operand
            addr = const_addr_of(operand)
            if addr
              addr[:offset] && addr[:offset] != 0 ? addr : { kind: :ref, name: addr[:name] }
            elsif operand.is_a?(AST::Identifier)
              { kind: :ref, name: operand.name }
            end
          else
            v = eval_const_init(expr.operand, allow_ref: allow_ref)
            case expr.op
            when :unary_minus then v.is_a?(Numeric) ? -v : nil
            when :bit_not     then v.is_a?(Integer) ? ~v : nil
            else nil
            end
          end
        when AST::BinaryOp
          l = eval_const_init(expr.left, allow_ref: allow_ref)
          r = eval_const_init(expr.right, allow_ref: allow_ref)
          return nil unless l.is_a?(Numeric) && r.is_a?(Numeric)
          case expr.op
          when :plus   then l + r
          when :minus  then l - r
          when :star   then l * r
          when :slash  then r != 0 ? l / r : nil
          when :percent then r != 0 ? l % r : nil
          when :lshift then l << r
          when :rshift then l >> r
          when :amp    then l & r
          when :pipe   then l | r
          when :caret  then l ^ r
          when :eq     then l == r ? 1 : 0
          when :neq    then l != r ? 1 : 0
          when :lt     then l < r ? 1 : 0
          when :leq    then l <= r ? 1 : 0
          when :gt     then l > r ? 1 : 0
          when :geq    then l >= r ? 1 : 0
          when :logical_and then (l != 0 && r != 0) ? 1 : 0
          when :logical_or  then (l != 0 || r != 0) ? 1 : 0
          end
        when AST::TernaryOp
          cond = eval_const_init(expr.cond, allow_ref: allow_ref)
          return nil unless cond.is_a?(Numeric)
          eval_const_init(cond != 0 ? expr.then_expr : expr.else_expr, allow_ref: allow_ref)
        when Hash
          if expr[:kind] == :initializer_list
            { kind: :initializer_list,
              items: (expr[:items] || []).map { |item|
                { designators: (item[:designators] || []).map { |designator|
                    designator[0] == :index ? [:index, eval_const_init(designator[1], allow_ref: false)] : designator
                  },
                  value: eval_const_init(item[:value], allow_ref: true) }
              } }
          end
        else nil
        end
      end

      # Recursively resolve a constant lvalue expression to {kind: :ref, name:, offset:}.
      # Handles &arr[i], &arr[i][j], &arr[i][j][k], &struct.field, etc.
      def const_addr_of(expr)
        case expr
        when AST::Identifier
          { kind: :ref, name: expr.name, offset: 0 }
        when AST::IndexExpr
          base_addr = const_addr_of(expr.array)
          return nil unless base_addr
          idx = eval_const_init(expr.index, allow_ref: false)
          return nil unless idx.is_a?(Integer)
          arr_ct = expr.array.ctype || infer_node_ctype(expr.array)
          esz = elem_size_for(arr_ct)
          { kind: :ref, name: base_addr[:name], offset: base_addr[:offset] + idx * esz }
        when AST::MemberExpr
          # dot-access only; arrow requires runtime dereference
          return nil if expr.arrow
          base_addr = const_addr_of(expr.expr)
          return nil unless base_addr
          struct_ct = expr.expr.ctype || infer_node_ctype(expr.expr)
          return nil unless struct_ct
          struct_ct = struct_ct.unqualified if struct_ct.respond_to?(:unqualified)
          return nil unless struct_ct.is_a?(OCC::Types::StructType) && struct_ct.complete?
          field = struct_ct.fields.find { |f| f[:name] == expr.member }
          return nil unless field
          { kind: :ref, name: base_addr[:name], offset: base_addr[:offset] + field[:offset] }
        else
          nil
        end
      end

      # ── Statement builders ──────────────────────────────────────────────────

      def build_stmt(node)
        case node
        when AST::CompoundStmt  then with_local_scope { node.items.each { |item| build_block_item(item) } }
        when AST::ExprStmt      then build_expr(node.expr) if node.expr
        when AST::AsmStmt       then build_asm(node)
        when AST::ReturnStmt    then build_return(node)
        when AST::IfStmt        then build_if(node)
        when AST::WhileStmt     then build_while(node)
        when AST::DoWhileStmt   then build_do_while(node)
        when AST::ForStmt       then build_for(node)
        when AST::SwitchStmt    then build_switch(node)
        when AST::BreakStmt     then emit(Jump.new(@break_target)) if @break_target
        when AST::ContinueStmt  then emit(Jump.new(@cont_target))  if @cont_target
        when AST::LabelStmt     then build_label_stmt(node)
        when AST::GotoStmt      then emit(Jump.new(node.label))
        when AST::IndirectGotoStmt
          target = build_expr(node.expr)
          emit(IndirectJump.new(target))
        when AST::CaseStmt
          # C allows case labels nested inside compound statements within a switch.
          # If this label was registered in the current switch's case_map (by
          # scan_nested_cases), switch to its block; otherwise just emit the body.
          if @switch_case_map && (val = eval_case_value(node.value)) &&
              (blk = @switch_case_map[val]) && !@block.equal?(blk)
            jump_to(blk) unless @block&.terminated?
            switch_to(blk)
          end
          build_stmt(node.stmt) if node.stmt
        when AST::DefaultStmt
          if @switch_default_block && !@block.equal?(@switch_default_block)
            jump_to(@switch_default_block) unless @block&.terminated?
            switch_to(@switch_default_block)
          end
          build_stmt(node.stmt) if node.stmt
        end
      end

      def build_block_item(item)
        case item
        when AST::Declaration then build_local_decl(item)
        else build_stmt(item)
        end
      end

      def build_local_decl(decl)
        # Collect enum constants from inline enum/struct definitions (including nested enums in structs).
        collect_enum_constants(decl.specifiers.tag_decl) if decl.specifiers.tag_decl

        is_static = decl.specifiers.storage == :static ||
                    decl.specifiers.storage == :_Thread_local
        is_extern = decl.specifiers.storage == :extern

        decl.declarators.each do |d|
          next unless d[:name]
          ctype = d[:resolved_type]

          if is_extern
            # extern declarations introduce no storage in this TU; just record the
            # ctype so identifier resolution can still consult it.
            @local_ctypes[d[:name]] = ctype if ctype
            next
          end

          if is_static
            # Static locals have static storage duration: emit as a global with a
            # mangled name so addresses persist across calls and there is no
            # collision with file-scope names or static locals in other functions.
            # Multiple declarations with the same C name in different block scopes
            # (e.g. repeated CONST_ID expansions) each need their own BSS slot.
            base_mangled = "__static_#{@func.name}_#{d[:name]}"
            idx = @static_local_counts[base_mangled] || 0
            @static_local_counts[base_mangled] = idx + 1
            mangled = idx == 0 ? base_mangled : "#{base_mangled}_#{idx}"
            init_val = d[:init] ? eval_const_init(d[:init], allow_ref: true) : nil
            @mod.add_global(mangled, ctype || 'int', init_val, static: true)
            @static_locals[d[:name]] = mangled
            @local_ctypes[d[:name]] = ctype if ctype
            next
          end

          # Block-scoped function declarations (e.g. `void foo(void);`) are
          # prototypes — they introduce a name but allocate no stack storage.
          # Register the function so calls to it are emitted as direct bl, not
          # as loads through a (garbage) stack slot.
          if ctype.is_a?(OCC::Types::FunctionType)
            @mod.mark_func(d[:name])
            @mod.mark_variadic(d[:name], ctype.params.length) if ctype.variadic
            @mod.mark_fp_func(d[:name]) if ctype.return_type.is_a?(OCC::Types::FloatingType)
            next
          end

          slot  = new_temp
          # Alloca defines frame layout, not executable control flow. Keep it
          # even if the declaration appears after a terminator but before a
          # label that can be reached by goto (CRuby's int_pow does this).
          @block << Alloca.new(slot, ctype || 'int')
          @locals[d[:name]] = slot
          @local_ctypes[d[:name]] = ctype if ctype

          if d[:init]
            if d[:init].is_a?(Hash) && d[:init][:kind] == :initializer_list
              addr = new_temp
              emit(AddrOf.new(addr, slot))
              build_initializer_list(addr, d[:init], ctype)
            elsif d[:init].is_a?(AST::StringLiteral) && ctype.is_a?(OCC::Types::ArrayType)
              # `const char arr[] = "str"` — copy bytes directly into the stack slot so
              # AddrOf(slot) gives the correct array base address (not a pointer-to-pointer).
              bytes = d[:init].value.bytes
              bytes << 0 unless bytes.empty? || bytes.last == 0  # ensure null terminator
              # Pad to multiple of 8 for aligned 8-byte stores
              remainder = bytes.length % 8
              bytes += Array.new((8 - remainder) % 8, 0) if remainder != 0
              bytes.each_slice(8).with_index do |chunk, chunk_idx|
                packed = chunk.each_with_index.reduce(0) { |acc, (b, i)| acc | (b << (i * 8)) }
                if chunk_idx == 0
                  emit(Store.new(slot, Const.new(packed), nil, 8))
                else
                  base = new_temp
                  emit(AddrOf.new(base, slot))
                  ptr = new_temp
                  emit(Gep.new(ptr, base, Const.new(chunk_idx * 8), 1))
                  emit(Store.new(ptr, Const.new(packed), nil, 8))
                end
              end
            else
              val = build_expr(d[:init])
              val = cast_to_bool(val) if bool_type?(ctype)
              # For struct-typed locals, pass the byte size so the codegen emits a
              # proper struct copy (ldp/stp) rather than storing the source pointer.
              esz = if ctype.is_a?(OCC::Types::StructType) && ctype.complete?
                       ctype.size rescue 8
                     else
                       8
                     end
              emit(Store.new(slot, val, ctype, esz))
            end
          end
        end
      end

      # Resolve an identifier name to the actual storage name. For static locals
      # this returns the mangled global name; otherwise it returns the name as-is.
      def global_name_for(name)
        @static_locals[name] || name
      end

      # Read-modify-write a bitfield in a struct initializer.
      # fptr points to the group start (field[:offset] within the struct base).
      # Computes byte_start from bit_offset, loads the minimum power-of-2 unit,
      # clears the field's bits, ORs in val, and stores back.
      def write_bitfield_init(fptr, field, val)
        raw_bit_offset = field[:bit_offset]
        byte_start     = raw_bit_offset / 8
        adj_bit_offset = raw_bit_offset % 8
        total_bits     = adj_bit_offset + field[:bit_width]
        load_size      = total_bits <= 8 ? 1 : total_bits <= 16 ? 2 : total_bits <= 32 ? 4 : 8

        unit_ptr = if byte_start.zero?
                     fptr
                   else
                     t = new_temp
                     emit(Binary.new(t, :plus, fptr, Const.new(byte_start)))
                     t
                   end

        old_unit   = new_temp
        emit(Load.new(old_unit, unit_ptr, nil, load_size))
        mask        = (1 << field[:bit_width]) - 1
        clear_mask  = ~(mask << adj_bit_offset) & 0xFFFF_FFFF_FFFF_FFFF
        cleared     = new_temp
        emit(Binary.new(cleared, :amp, old_unit, Const.new(clear_mask)))
        val_masked  = new_temp
        emit(Binary.new(val_masked, :amp, val, Const.new(mask)))
        val_shifted = new_temp
        emit(Binary.new(val_shifted, :lshift, val_masked, Const.new(adj_bit_offset)))
        new_unit    = new_temp
        emit(Binary.new(new_unit, :pipe, cleared, val_shifted))
        emit(Store.new(unit_ptr, new_unit, nil, load_size))
      end

      # Emit stores for a brace-enclosed initializer list into memory starting at base_ptr.
      def build_initializer_list(base_ptr, init_list, ctype)
        items = init_list[:items] || []

        if ctype.is_a?(OCC::Types::StructType) && ctype.complete?
          # Zero-initialize all fields first (C11 §6.7.9 ¶10: unspecified members are zero).
          # Bitfields use read-modify-write to correctly handle packed groups where multiple
          # fields share the same storage unit bytes.
          ctype.fields.each do |field|
            next unless field[:name]
            fptr = if field[:offset].zero?
                     base_ptr
                   else
                     t = new_temp
                     emit(Binary.new(t, :plus, base_ptr, Const.new(field[:offset])))
                     t
                   end
            if field[:bit_width]
              write_bitfield_init(fptr, field, Const.new(0))
            else
              esz = field[:type].size rescue 8
              emit(Store.new(fptr, Const.new(0), field[:type], esz))
            end
          end
          # Then apply explicit initializers
          items.each_with_index do |item, seq_idx|
            # Resolve the field at this aggregate level. Nested designators are
            # consumed one aggregate at a time, e.g. `.as.string = { ... }`.
            designators = item[:designators] || []
            field_idx = designators.index { |d| d[0] == :field }
            field = if field_idx
                      ctype.fields.find { |f| f[:name] == designators[field_idx].last }
                    else
                      ctype.fields[seq_idx]
                    end
            next unless field && item[:value]
            fptr = if field[:offset].zero?
                     base_ptr
                   else
                     t = new_temp
                     emit(Binary.new(t, :plus, base_ptr, Const.new(field[:offset])))
                     t
                   end

            remaining_designators = field_idx ? designators[(field_idx + 1)..] : []
            if remaining_designators && !remaining_designators.empty?
              build_initializer_list(
                fptr,
                { kind: :initializer_list, items: [{ designators: remaining_designators, value: item[:value] }] },
                field[:type]
              )
            elsif item[:value].is_a?(Hash) && item[:value][:kind] == :initializer_list
              build_initializer_list(fptr, item[:value], field[:type])
            elsif field[:bit_width]
              val = build_expr(item[:value])
              write_bitfield_init(fptr, field, val)
            else
              val = build_expr(item[:value])
              esz = field[:type].size rescue 8
              emit(Store.new(fptr, val, field[:type], esz))
            end
          end
        elsif ctype.is_a?(OCC::Types::ArrayType)
          elem_ct = ctype.element
          esz     = elem_ct.size rescue 8
          if ctype.count
            total = ctype.count * esz
            emit(Store.new(base_ptr, Const.new(0), ctype, total)) if total > 0
          end
          items.each_with_index do |item, seq_idx|
            next unless item[:value]
            idx = if item[:designators]&.any? { |d| d[0] == :index }
                    build_expr(item[:designators].find { |d| d[0] == :index }[1])
                  else
                    Const.new(seq_idx)
                  end
            eptr = new_temp
            emit(Gep.new(eptr, base_ptr, idx, esz))
            if item[:value].is_a?(Hash) && item[:value][:kind] == :initializer_list
              build_initializer_list(eptr, item[:value], elem_ct)
            else
              val = build_expr(item[:value])
              emit(Store.new(eptr, val, elem_ct, esz))
            end
          end
        else
          # Scalar or unknown: store first value directly
          val = build_expr(items.first[:value]) if items.first
          emit(Store.new(base_ptr, val)) if val
        end
      end

      def build_asm(node)
        return unless node.template.match?(/\bmov\b.*%0.*\b(?:sp|rsp)\b/)

        node.outputs.each do |out|
          next unless out[:constraint].start_with?('=')

          addr = lvalue_addr(out[:expr])
          sp = new_temp
          emit(StackPointer.new(sp))
          ct = out[:expr].respond_to?(:ctype) ? out[:expr].ctype : nil
          sz = ct.respond_to?(:size) ? (ct.size rescue 8) : 8
          emit(Store.new(addr, sp, ct, sz))
        end
      end

      def build_return(node)
        if node.value
          val = build_expr(node.value)
          # Implicit narrowing coercion: return (int)(-244) in a uint8_t function → truncate
          ret_ct = @func_ret_ctype
          val_ct = node.value.respond_to?(:ctype) ? node.value.ctype : nil
          if ret_ct && val_ct
            ret_inner = ret_ct.respond_to?(:unqualified) ? ret_ct.unqualified : ret_ct
            val_inner = val_ct.respond_to?(:unqualified) ? val_ct.unqualified : val_ct
            if bool_type?(ret_inner)
              cast_tmp = new_temp
              emit(Cast.new(cast_tmp, val, ret_inner.to_s, ret_inner))
              val = cast_tmp
            elsif ret_inner.is_a?(OCC::Types::IntegerType) &&
               val_inner.is_a?(OCC::Types::IntegerType) &&
               ret_inner.size < val_inner.size &&
               ret_inner.size < 4  # only sub-int widths need explicit truncation
              cast_tmp = new_temp
              emit(Cast.new(cast_tmp, val, ret_inner.to_s, ret_ct))
              val = cast_tmp
            end
          end
          emit(Return.new(val))
        else
          emit(Return.new)
        end
      end

      def build_if(node)
        cond_val    = build_expr(node.cond)
        then_block  = new_block(new_label('if_then'))
        else_block  = node.else_body ? new_block(new_label('if_else')) : nil
        merge_block = new_block(new_label('if_end'))

        emit(CondJump.new(cond_val, then_block.label, (else_block || merge_block).label))

        switch_to(then_block)
        build_stmt(node.then_body)
        jump_to(merge_block) unless @block.terminated?

        if node.else_body
          switch_to(else_block)
          build_stmt(node.else_body)
          jump_to(merge_block) unless @block.terminated?
        end

        switch_to(merge_block)
      end

      def build_while(node)
        cond_block = new_block(new_label('while_cond'))
        body_block = new_block(new_label('while_body'))
        end_block  = new_block(new_label('while_end'))

        saved_break = @break_target
        saved_cont  = @cont_target
        @break_target = end_block.label
        @cont_target  = cond_block.label

        jump_to(cond_block)
        switch_to(cond_block)
        cond_val = build_expr(node.cond)
        emit(CondJump.new(cond_val, body_block.label, end_block.label))

        switch_to(body_block)
        build_stmt(node.body)
        jump_to(cond_block) unless @block.terminated?

        switch_to(end_block)

        @break_target = saved_break
        @cont_target  = saved_cont
      end

      def build_do_while(node)
        body_block = new_block(new_label('do_body'))
        cond_block = new_block(new_label('do_cond'))
        end_block  = new_block(new_label('do_end'))

        saved_break = @break_target
        saved_cont  = @cont_target
        @break_target = end_block.label
        @cont_target  = cond_block.label

        jump_to(body_block)
        switch_to(body_block)
        build_stmt(node.body)
        jump_to(cond_block) unless @block.terminated?

        switch_to(cond_block)
        cond_val = build_expr(node.cond)
        emit(CondJump.new(cond_val, body_block.label, end_block.label))

        switch_to(end_block)

        @break_target = saved_break
        @cont_target  = saved_cont
      end

      def build_for(node)
        with_local_scope do
          cond_block = new_block(new_label('for_cond'))
          body_block = new_block(new_label('for_body'))
          incr_block = new_block(new_label('for_incr'))
          end_block  = new_block(new_label('for_end'))

          saved_break = @break_target
          saved_cont  = @cont_target
          @break_target = end_block.label
          @cont_target  = incr_block.label

          build_block_item(node.init) if node.init
          jump_to(cond_block)

          switch_to(cond_block)
          if node.cond
            cond_val = build_expr(node.cond)
            emit(CondJump.new(cond_val, body_block.label, end_block.label))
          else
            emit(Jump.new(body_block.label))
          end

          switch_to(body_block)
          build_stmt(node.body)
          jump_to(incr_block) unless @block.terminated?

          switch_to(incr_block)
          build_expr(node.update) if node.update
          jump_to(cond_block)

          switch_to(end_block)

          @break_target = saved_break
          @cont_target  = saved_cont
        end
      end

      def build_switch(node)
        switch_val  = build_expr(node.expr)
        saved_break         = @break_target
        saved_case_map      = @switch_case_map
        saved_default_block = @switch_default_block

        items = node.body.is_a?(AST::CompoundStmt) ? node.body.items : [node.body]

        # First pass: collect ALL case values (including those nested inside case bodies)
        # and create blocks. Fall-through chains (case A: case B: body) share one block.
        case_map      = {}   # integer_value => BasicBlock
        default_block = nil

        items.each do |item|
          case item
          when AST::CaseStmt
            # Walk the chain of adjacent CaseStmts at this level.
            chain_vals = []
            s = item
            while s.is_a?(AST::CaseStmt)
              v = eval_case_value(s.value)
              chain_vals << v if v && !case_map.key?(v)
              s = s.stmt
            end
            blk = new_block(new_label('switch_case'))
            chain_vals.each { |v| case_map[v] = blk }
            # Also scan the non-case body for case labels nested inside compound stmts.
            scan_nested_cases(s, case_map)
          when AST::DefaultStmt
            default_block ||= new_block(new_label('switch_default'))
            scan_nested_cases(item.stmt, case_map)
          else
            scan_nested_cases(item, case_map)
          end
        end

        end_block             = new_block(new_label('switch_end'))
        @break_target         = end_block.label
        @switch_case_map      = case_map
        @switch_default_block = default_block

        # Emit dispatch: one comparison + conditional jump per case value
        case_map.each do |val, blk|
          cmp = new_temp
          emit(Binary.new(cmp, :eq, switch_val, Const.new(val)))
          next_check = new_block(new_label('switch_check'))
          emit(CondJump.new(cmp, blk.label, next_check.label))
          switch_to(next_check)
        end
        emit(Jump.new(default_block ? default_block.label : end_block.label))

        # Second pass: emit body items in order, switching to case blocks as encountered.
        items.each do |item|
          case item
          when AST::CaseStmt
            val = eval_case_value(item.value)
            next if val.nil?
            blk = case_map[val]
            jump_to(blk) unless @block&.terminated?
            switch_to(blk)
            build_stmt(item.stmt) if item.stmt
          when AST::DefaultStmt
            jump_to(default_block) unless @block&.terminated?
            switch_to(default_block)
            build_stmt(item.stmt) if item.stmt
          else
            build_block_item(item)
          end
        end

        jump_to(end_block) unless @block&.terminated?
        switch_to(end_block)
        @break_target         = saved_break
        @switch_case_map      = saved_case_map
        @switch_default_block = saved_default_block
      end

      # Recursively find case labels nested inside compound statements within a case body,
      # and register them in case_map. This handles C's rule that case labels inside nested
      # blocks (e.g. the fall-through pattern "case A: { ...; case B: body }") are still
      # valid dispatch targets for the enclosing switch.
      def scan_nested_cases(stmt, case_map)
        return unless stmt
        case stmt
        when AST::CaseStmt
          chain_vals = []
          s = stmt
          while s.is_a?(AST::CaseStmt)
            v = eval_case_value(s.value)
            chain_vals << v if v && !case_map.key?(v)
            s = s.stmt
          end
          unless chain_vals.empty?
            blk = new_block(new_label('switch_case'))
            chain_vals.each { |v| case_map[v] = blk }
          end
          scan_nested_cases(s, case_map)
        when AST::DefaultStmt
          scan_nested_cases(stmt.stmt, case_map)
        when AST::CompoundStmt
          stmt.items.each { |i| scan_nested_cases(i, case_map) }
        when AST::IfStmt
          scan_nested_cases(stmt.then_body, case_map)
          scan_nested_cases(stmt.else_body, case_map) if stmt.else_body
        when AST::WhileStmt, AST::DoWhileStmt
          scan_nested_cases(stmt.body, case_map)
        when AST::ForStmt
          scan_nested_cases(stmt.body, case_map)
        end
      end

      # Evaluate a constant expression to an integer, or nil if it can't be folded.
      def eval_case_value(expr)
        case expr
        when AST::IntLiteral  then expr.integer_value
        when AST::CharLiteral then char_lit_int(expr.value)
        when AST::Identifier  then @enum_constants[expr.name]
        when AST::Cast        then eval_case_value(expr.expr)
        when AST::UnaryOp
          v = eval_case_value(expr.operand)
          case expr.op
          when :unary_plus  then v
          when :unary_minus then v ? -v : nil
          when :bit_not     then v.is_a?(Integer) ? ~v : nil
          else nil
          end
        when AST::BinaryOp
          l = eval_case_value(expr.left)
          r = eval_case_value(expr.right)
          return nil unless l && r
          case expr.op
          when :plus   then l + r
          when :minus  then l - r
          when :star   then l * r
          when :amp    then l & r
          when :pipe   then l | r
          when :caret  then l ^ r
          when :lshift then l << r
          when :rshift then l >> r
          end
        when AST::CallExpr
          # Constant-fold calls to simple inline functions (e.g. RB_INT2FIX in Ruby headers).
          # GCC/Clang allow inline function calls in case labels by constant-folding them.
          func_name = expr.callee.is_a?(AST::Identifier) ? expr.callee.name : nil
          return nil unless func_name
          fn = @func_ast_defs[func_name]
          return nil unless fn&.body
          args = expr.args.map { |a| eval_case_value(a) }
          return nil if args.any?(&:nil?)
          eval_inline_func_body(fn, args)
        else nil
        end
      end

      # Evaluate a simple inline function body with constant arguments.
      # Returns an Integer or nil if the body is too complex to evaluate.
      def eval_inline_func_body(fn, const_args)
        params = fn.params[:params]
        return nil if params.length != const_args.length
        env = {}
        params.zip(const_args) { |p, v| env[p[:name]] = v if p[:name] }
        eval_inline_stmts(fn.body.items, env)
      rescue
        nil
      end

      def eval_inline_stmts(items, env)
        items.each do |item|
          case item
          when AST::Declaration
            item.declarators.each do |d|
              next unless d[:name]
              val = d[:init] ? eval_inline_expr(d[:init], env) : 0
              return nil if val.nil?
              env[d[:name]] = val
            end
          when AST::ReturnStmt
            return eval_inline_expr(item.value, env)
          when AST::ExprStmt
            # skip (void)0 assertions and other expression statements
          else
            return nil  # complex control flow — give up
          end
        end
        nil
      end

      def eval_inline_expr(expr, env)
        return nil unless expr
        case expr
        when AST::IntLiteral   then expr.integer_value
        when AST::CharLiteral  then expr.value.ord
        when AST::Identifier   then env.key?(expr.name) ? env[expr.name] : @enum_constants[expr.name]
        when AST::Cast
          v = eval_inline_expr(expr.expr, env)
          return nil unless v
          # Apply truncation for sized integer types. Use the raw type keywords since
          # we don't have full type resolution in this context.
          specs = expr.type_spec[:specs] rescue nil
          if specs
            kwds = specs.respond_to?(:type_keywords) ? specs.type_keywords : []
            unsigned = kwds.include?(:unsigned) || (!kwds.include?(:signed) && kwds.include?(:long) &&
                                                     specs.respond_to?(:storage) && specs.storage.nil?)
            size_bits = if kwds.include?(:char)   then 8
                        elsif kwds.include?(:short) then 16
                        elsif kwds.include?(:int)   then 32
                        elsif kwds.include?(:long)  then 64
                        end
            if size_bits
              mask = (1 << size_bits) - 1
              v &= mask
              # Sign-extend if signed
              if !unsigned && v >= (1 << (size_bits - 1))
                v -= (1 << size_bits)
              end
            end
          end
          v
        when AST::UnaryOp
          v = eval_inline_expr(expr.operand, env)
          return nil unless v
          case expr.op
          when :unary_plus  then v
          when :unary_minus then -v
          when :bit_not     then ~v
          when :logical_not then v == 0 ? 1 : 0
          else nil
          end
        when AST::BinaryOp
          l = eval_inline_expr(expr.left, env)
          r = eval_inline_expr(expr.right, env)
          return nil unless l && r
          case expr.op
          when :plus    then l + r
          when :minus   then l - r
          when :star    then l * r
          when :amp     then l & r
          when :pipe    then l | r
          when :caret   then l ^ r
          when :lshift  then l << r
          when :rshift  then l >> r
          when :slash   then r != 0 ? l / r : nil
          when :percent then r != 0 ? l % r : nil
          else nil
          end
        when AST::TernaryOp
          c = eval_inline_expr(expr.cond, env)
          return nil if c.nil?
          c != 0 ? eval_inline_expr(expr.then_expr, env) : eval_inline_expr(expr.else_expr, env)
        when AST::CallExpr
          func_name = expr.callee.is_a?(AST::Identifier) ? expr.callee.name : nil
          return nil unless func_name
          fn = @func_ast_defs[func_name]
          return nil unless fn&.body
          args = expr.args.map { |a| eval_inline_expr(a, env) }
          return nil if args.any?(&:nil?)
          eval_inline_func_body(fn, args)
        else nil
        end
      end

      def build_label_stmt(node)
        lbl_block = new_block(node.name)
        jump_to(lbl_block)
        switch_to(lbl_block)
        build_stmt(node.stmt)
      end

      # ── Expression builders ─────────────────────────────────────────────────
      # Each returns an operand (Temp, Const, or GlobalRef).

      def build_expr(node)
        return Const.new(0) unless node

        case node
        when AST::IntLiteral    then Const.new(node.integer_value)
        when AST::FloatLiteral  then Const.new(node.raw.to_f)
        when AST::CharLiteral   then Const.new(char_lit_int(node.value))
        when AST::StringLiteral then @mod.add_string(node.value)
        when AST::LabelAddr     then LabelRef.new(@func.name, node.name)
        when AST::Identifier    then build_ident(node)
        when AST::BinaryOp      then build_binop(node)
        when AST::UnaryOp       then build_unary(node)
        when AST::Assign        then build_assign(node)
        when AST::CallExpr      then build_call(node)
        when AST::TernaryOp     then build_ternary(node)
        when AST::Cast          then build_cast(node)
        when AST::IndexExpr     then build_index(node)
        when AST::MemberExpr    then build_member(node)
        when AST::SizeofType    then build_sizeof_type(node)
        when AST::SizeofExpr    then build_sizeof_expr(node)
        when AST::BuiltinOffsetof then Const.new(node.sizeof_val || 0)
        when AST::StmtExpr      then build_stmt_expr(node)
        when AST::CommaExpr
          node.exprs.map { |e| build_expr(e) }.last
        when Hash
          # _Generic(...) — semantic analyzer annotates [:selected_expr]
          if node[:kind] == :generic
            sel = node[:selected_expr]
            sel ? build_expr(sel) : Const.new(0)
          else
            Const.new(0)
          end
        else
          Const.new(0)
        end
      end

      def build_ident(node)
        # Enum constants are compile-time integer values, not addressable storage.
        return Const.new(@enum_constants[node.name]) if @enum_constants.key?(node.name)

        slot = @locals[node.name]
        if slot
          # Arrays and struct values decay to a pointer to their storage when
          # used as an expression value. When node.ctype is nil (e.g. inside a
          # struct initializer list that semantic analysis skipped), fall back
          # to @local_ctypes for the decay check.
          local_ctype = node.ctype || @local_ctypes[node.name]
          if local_ctype.is_a?(OCC::Types::ArrayType) ||
             local_ctype.is_a?(OCC::Types::StructType)
            t = new_temp
            emit(AddrOf.new(t, slot))
            t
          else
            t = new_temp
            emit(Load.new(t, slot, node.ctype))
            t
          end
        else
          # Global variable (or static local, which is emitted as a mangled
          # global). Arrays and structs used in expressions yield their address.
          gname = global_name_for(node.name)
          global_ctype = node.ctype || @local_ctypes[node.name] ||
                         (@mod.globals[gname]&.dig(:type))
          if global_ctype.is_a?(OCC::Types::ArrayType) ||
             global_ctype.is_a?(OCC::Types::StructType)
            t = new_temp
            emit(AddrOf.new(t, GlobalRef.new(gname)))
            t
          else
            GlobalRef.new(gname)
          end
        end
      end

      def build_binop(node)
        # && and || require short-circuit evaluation.
        return build_logical_and(node) if node.op == :logical_and
        return build_logical_or(node)  if node.op == :logical_or

        # Pointer arithmetic: pointer ± integer must scale by element size.
        if node.op == :plus || node.op == :minus
          lct = node.left.ctype
          rct = node.right.ctype
          if node.op == :plus
            if pointer_ctype?(lct)
              esz = elem_size_for(lct)
              left  = build_expr(node.left)
              right = build_expr(node.right)
              dst = new_temp
              emit(Gep.new(dst, left, right, esz))
              return dst
            elsif pointer_ctype?(rct)
              esz = elem_size_for(rct)
              left  = build_expr(node.left)
              right = build_expr(node.right)
              dst = new_temp
              emit(Gep.new(dst, right, left, esz))   # pointer is base
              return dst
            end
          elsif node.op == :minus && pointer_ctype?(lct) && !pointer_ctype?(rct)
            esz = elem_size_for(lct)
            left  = build_expr(node.left)
            right = build_expr(node.right)
            neg   = new_temp
            emit(Unary.new(neg, :neg, right))
            dst = new_temp
            emit(Gep.new(dst, left, neg, esz))
            return dst
          elsif node.op == :minus && pointer_ctype?(lct) && pointer_ctype?(rct)
            # Pointer subtraction: (p1 - p2) in elements = byte_diff / element_size
            esz   = elem_size_for(lct)
            left  = build_expr(node.left)
            right = build_expr(node.right)
            byte_diff = new_temp
            emit(Binary.new(byte_diff, :minus, left, right))
            if esz > 1
              dst = new_temp
              emit(Binary.new(dst, :slash, byte_diff, Const.new(esz)))
              return dst
            end
            return byte_diff
          end
        end

        left  = build_expr(node.left)
        right = build_expr(node.right)
        dst   = new_temp
        op    = node.op
        # For comparison/division/rshift, respect signedness of operands.
        # Apply C's usual arithmetic conversions: when one operand is unsigned
        # and the other is signed, use unsigned only if the unsigned type's rank
        # (approximated by size) >= the signed type's rank. Otherwise the signed
        # type dominates and the operation is signed.
        # FP types never use unsigned comparison variants (float has no signed/unsigned).
        if %i[gt lt geq leq eq neq slash percent rshift].include?(op)
          lct = node.left.ctype
          rct = node.right.ctype
          lct_inner = lct.respond_to?(:unqualified) ? lct.unqualified : lct
          rct_inner = rct.respond_to?(:unqualified) ? rct.unqualified : rct
          fp_compare = lct_inner.is_a?(OCC::Types::FloatingType) ||
                       rct_inner.is_a?(OCC::Types::FloatingType)
          unless fp_compare
            lct_unsigned = unsigned_ctype?(lct)
            rct_unsigned = unsigned_ctype?(rct)
            unsigned = if pointer_ctype?(lct) && pointer_ctype?(rct)
                         true
                       elsif lct_unsigned && rct_unsigned
                         true
                       elsif lct_unsigned && !rct_unsigned
                         # C §6.3.1.8: unsigned comparison only if the unsigned
                         # type has rank >= int (size >= 4). Sub-int unsigned types
                         # (uint8_t, uint16_t) are promoted to signed int first.
                         ls = lct_inner.respond_to?(:size) ? lct_inner.size.to_i : 8
                         rs = rct_inner.respond_to?(:size) ? rct_inner.size.to_i : 8
                         ls >= rs && ls >= 4
                       elsif !lct_unsigned && rct_unsigned
                         # Same rule on the other side
                         ls = lct_inner.respond_to?(:size) ? lct_inner.size.to_i : 8
                         rs = rct_inner.respond_to?(:size) ? rct_inner.size.to_i : 8
                         rs >= ls && rs >= 4
                       else
                         false
                       end
            if unsigned
              op = case op
                   when :gt    then :ugt
                   when :lt    then :ult
                   when :geq   then :ugeq
                   when :leq   then :uleq
                   when :slash then :udiv
                   when :percent then :umod
                   when :rshift  then :urshift
                   else op
                   end
              # C §6.3.1.8: when unsigned wins, the signed operand is converted
              # to the unsigned type. For uint32_t vs int32_t: int32_t(-1)
              # sign-extends to 0xFFFFFFFFFFFFFFFF in a 64-bit register =
              # UINT64_MAX, not UINT32_MAX. Cast signed to uint32_t to zero-
              # extend correctly before the unsigned comparison.
              # For uint64_t vs int32_t: int32_t sign-extends to the correct
              # uint64_t representation already (e.g. -7 → 0xFFFFFFF9 in 32
              # bits, but 0xFFFFFFFFFFFFFFF9 sign-extended = correct uint64).
              # Only cast when the unsigned side is also 4 bytes.
              if lct_unsigned && !rct_unsigned &&
                 rct_inner.is_a?(OCC::Types::IntegerType) && rct_inner.size == 4 &&
                 lct_inner.respond_to?(:size) && lct_inner.size.to_i == 4
                unsigned_ct = OCC::Types::UINT
                cast_t = new_temp
                emit(Cast.new(cast_t, right, unsigned_ct.to_s, unsigned_ct))
                right = cast_t
              elsif !lct_unsigned && rct_unsigned &&
                    lct_inner.is_a?(OCC::Types::IntegerType) && lct_inner.size == 4 &&
                    rct_inner.respond_to?(:size) && rct_inner.size.to_i == 4
                unsigned_ct = OCC::Types::UINT
                cast_t = new_temp
                emit(Cast.new(cast_t, left, unsigned_ct.to_s, unsigned_ct))
                left = cast_t
              end
            end
          end
        end
        emit(Binary.new(dst, op, left, right, node.ctype))
        dst
      end

      # True if ctype is an unsigned integer type (not signed, not pointer).
      def unsigned_ctype?(ct)
        return false unless ct
        inner = ct.respond_to?(:unqualified) ? ct.unqualified : ct
        inner.is_a?(OCC::Types::IntegerType) && !inner.signed?
      end

      # True if ctype is a pointer or array (decays to pointer in arithmetic).
      def pointer_ctype?(ct)
        return false unless ct
        inner = ct.respond_to?(:unqualified) ? ct.unqualified : ct
        inner.is_a?(OCC::Types::PointerType) || inner.is_a?(OCC::Types::ArrayType)
      end

      def fp_type?(ct)
        return false unless ct
        inner = ct.respond_to?(:unqualified) ? ct.unqualified : ct
        inner.is_a?(OCC::Types::FloatingType)
      end

      # Compile `a && b` with short-circuit: if a is false, result = 0 without evaluating b.
      def build_logical_and(node)
        slot = new_temp
        emit(Alloca.new(slot, nil))
        emit(Store.new(slot, Const.new(0)))  # default: false

        lhs       = build_expr(node.left)
        rhs_block = new_block(new_label('land_rhs'))
        end_block = new_block(new_label('land_end'))

        emit(CondJump.new(lhs, rhs_block.label, end_block.label))
        switch_to(rhs_block)

        rhs        = build_expr(node.right)
        true_block = new_block(new_label('land_true'))
        emit(CondJump.new(rhs, true_block.label, end_block.label))
        switch_to(true_block)
        emit(Store.new(slot, Const.new(1)))
        emit(Jump.new(end_block.label))

        switch_to(end_block)
        dst = new_temp
        emit(Load.new(dst, slot))
        dst
      end

      # Compile `a || b` with short-circuit: if a is true, result = 1 without evaluating b.
      def build_logical_or(node)
        slot = new_temp
        emit(Alloca.new(slot, nil))
        emit(Store.new(slot, Const.new(1)))  # default: true

        lhs       = build_expr(node.left)
        rhs_block = new_block(new_label('lor_rhs'))
        end_block = new_block(new_label('lor_end'))

        emit(CondJump.new(lhs, end_block.label, rhs_block.label))
        switch_to(rhs_block)

        rhs         = build_expr(node.right)
        false_block = new_block(new_label('lor_false'))
        emit(CondJump.new(rhs, end_block.label, false_block.label))
        switch_to(false_block)
        emit(Store.new(slot, Const.new(0)))
        emit(Jump.new(end_block.label))

        switch_to(end_block)
        dst = new_temp
        emit(Load.new(dst, slot))
        dst
      end

      def maybe_truncate_narrow(val, ct)
        return val unless ct
        return cast_to_bool(val) if bool_type?(ct)
        return val unless ct.is_a?(OCC::Types::IntegerType) && ct.size < 4
        trunc = new_temp
        emit(Cast.new(trunc, val, ct.to_s, ct))
        trunc
      end

      def bool_type?(ct)
        inner = ct.respond_to?(:unqualified) ? ct.unqualified : ct
        inner.is_a?(OCC::Types::BoolType)
      end

      def cast_to_bool(val)
        coerced = new_temp
        emit(Cast.new(coerced, val, '_Bool', OCC::Types::BOOL))
        coerced
      end

      def build_unary(node)
        case node.op
        when :addr_of
          dst = new_temp
          case node.operand
          when AST::Identifier
            slot = @locals[node.operand.name]
            if slot
              emit(AddrOf.new(dst, slot))
            else
              emit(AddrOf.new(dst, GlobalRef.new(global_name_for(node.operand.name))))
            end
          when AST::IndexExpr
            arr      = build_expr(node.operand.array)
            idx      = build_expr(node.operand.index)
            array_ct = node.operand.array.ctype || infer_node_ctype(node.operand.array)
            esz      = elem_size_for(array_ct)
            emit(Gep.new(dst, arr, idx, esz))
          when AST::MemberExpr
            return build_member_addr(node.operand)
          when AST::UnaryOp
            if node.operand.op == :deref
              # &(*ptr) == ptr — evaluate the inner pointer expression directly
              return build_expr(node.operand.operand)
            else
              emit(Copy.new(dst, build_expr(node.operand)))
            end
          else
            emit(Copy.new(dst, build_expr(node.operand)))
          end
          dst
        when :deref
          ptr = build_expr(node.operand)
          pointed_ct = node.operand.ctype.is_a?(OCC::Types::PointerType) ? node.operand.ctype.base : nil
          # Dereferencing a pointer to an array, struct, or function type yields
          # the storage/function address itself — no Load needed.
          # For functions: *fp == fp in C; loading from a function address would
          # read instruction bytes as data, producing a garbage function pointer.
          if pointed_ct.is_a?(OCC::Types::ArrayType) ||
             pointed_ct.is_a?(OCC::Types::StructType) ||
             pointed_ct.is_a?(OCC::Types::FunctionType)
            return ptr
          end
          elem_sz = elem_size_for(node.operand.ctype)
          dst = new_temp
          emit(Load.new(dst, ptr, pointed_ct, elem_sz))
          dst
        when :unary_minus
          operand = build_expr(node.operand)
          dst = new_temp
          emit(Unary.new(dst, :neg, operand))
          dst
        when :logical_not
          operand = build_expr(node.operand)
          dst = new_temp
          emit(Unary.new(dst, :not, operand))
          dst
        when :bit_not
          operand = build_expr(node.operand)
          dst = new_temp
          emit(Unary.new(dst, :bitnot, operand))
          # mvn works on 64-bit registers; truncate the result to the actual
          # operand width so e.g. ~(uint32_t)0 == 0xFFFF_FFFF not 0xFFFF...FF.
          ct = node.ctype
          if ct.is_a?(OCC::Types::IntegerType) && ct.size <= 4
            trunc = new_temp
            emit(Cast.new(trunc, dst, ct.to_s, ct))
            trunc
          else
            dst
          end
        when :pre_inc
          slot = @locals[node.operand.name] if node.operand.is_a?(AST::Identifier)
          ct = node.operand.ctype
          esz = pointer_ctype?(ct) ? elem_size_for(ct) : nil
          if slot
            old = new_temp; emit(Load.new(old, slot))
            new_val = new_temp
            if esz
              emit(Gep.new(new_val, old, Const.new(1), esz))
            else
              emit(Binary.new(new_val, :plus, old, Const.new(1)))
            end
            new_val = maybe_truncate_narrow(new_val, ct) unless esz
            emit(Store.new(slot, new_val))
            new_val
          elsif !esz && node.operand.is_a?(AST::MemberExpr) && (bf = bitfield_info(node.operand))
            old = build_member(node.operand)
            new_val = new_temp
            emit(Binary.new(new_val, :plus, old, Const.new(1)))
            emit_bitfield_rmw_store(node.operand, bf, new_val)
            new_val
          else
            addr = lvalue_addr(node.operand)
            sz = ct ? (ct.size rescue 8) : 8
            old = new_temp; emit(Load.new(old, addr, ct, sz))
            new_val = new_temp
            if esz
              emit(Gep.new(new_val, old, Const.new(1), esz))
            else
              emit(Binary.new(new_val, :plus, old, Const.new(1)))
            end
            new_val = maybe_truncate_narrow(new_val, ct) unless esz
            emit(Store.new(addr, new_val, nil, sz))
            new_val
          end
        when :post_inc
          slot = @locals[node.operand.name] if node.operand.is_a?(AST::Identifier)
          ct = node.operand.ctype
          esz = pointer_ctype?(ct) ? elem_size_for(ct) : nil
          if slot
            old = new_temp; emit(Load.new(old, slot))
            new_val = new_temp
            if esz
              emit(Gep.new(new_val, old, Const.new(1), esz))
            else
              emit(Binary.new(new_val, :plus, old, Const.new(1)))
            end
            new_val = maybe_truncate_narrow(new_val, ct) unless esz
            emit(Store.new(slot, new_val))
            old
          elsif !esz && node.operand.is_a?(AST::MemberExpr) && (bf = bitfield_info(node.operand))
            old = build_member(node.operand)
            new_val = new_temp
            emit(Binary.new(new_val, :plus, old, Const.new(1)))
            emit_bitfield_rmw_store(node.operand, bf, new_val)
            old
          else
            addr = lvalue_addr(node.operand)
            sz = ct ? (ct.size rescue 8) : 8
            old = new_temp; emit(Load.new(old, addr, ct, sz))
            new_val = new_temp
            if esz
              emit(Gep.new(new_val, old, Const.new(1), esz))
            else
              emit(Binary.new(new_val, :plus, old, Const.new(1)))
            end
            new_val = maybe_truncate_narrow(new_val, ct) unless esz
            emit(Store.new(addr, new_val, nil, sz))
            old
          end
        when :pre_dec
          slot = @locals[node.operand.name] if node.operand.is_a?(AST::Identifier)
          ct = node.operand.ctype
          esz = pointer_ctype?(ct) ? elem_size_for(ct) : nil
          if slot
            old = new_temp; emit(Load.new(old, slot))
            new_val = new_temp
            if esz
              emit(Gep.new(new_val, old, Const.new(-1), esz))
            else
              emit(Binary.new(new_val, :minus, old, Const.new(1)))
            end
            new_val = maybe_truncate_narrow(new_val, ct) unless esz
            emit(Store.new(slot, new_val))
            new_val
          elsif !esz && node.operand.is_a?(AST::MemberExpr) && (bf = bitfield_info(node.operand))
            old = build_member(node.operand)
            new_val = new_temp
            emit(Binary.new(new_val, :minus, old, Const.new(1)))
            emit_bitfield_rmw_store(node.operand, bf, new_val)
            new_val
          else
            addr = lvalue_addr(node.operand)
            sz = ct ? (ct.size rescue 8) : 8
            old = new_temp; emit(Load.new(old, addr, ct, sz))
            new_val = new_temp
            if esz
              emit(Gep.new(new_val, old, Const.new(-1), esz))
            else
              emit(Binary.new(new_val, :minus, old, Const.new(1)))
            end
            new_val = maybe_truncate_narrow(new_val, ct) unless esz
            emit(Store.new(addr, new_val, nil, sz))
            new_val
          end
        when :post_dec
          slot = @locals[node.operand.name] if node.operand.is_a?(AST::Identifier)
          ct = node.operand.ctype
          esz = pointer_ctype?(ct) ? elem_size_for(ct) : nil
          if slot
            old = new_temp; emit(Load.new(old, slot))
            new_val = new_temp
            if esz
              emit(Gep.new(new_val, old, Const.new(-1), esz))
            else
              emit(Binary.new(new_val, :minus, old, Const.new(1)))
            end
            new_val = maybe_truncate_narrow(new_val, ct) unless esz
            emit(Store.new(slot, new_val))
            old
          elsif !esz && node.operand.is_a?(AST::MemberExpr) && (bf = bitfield_info(node.operand))
            old = build_member(node.operand)
            new_val = new_temp
            emit(Binary.new(new_val, :minus, old, Const.new(1)))
            emit_bitfield_rmw_store(node.operand, bf, new_val)
            old
          else
            addr = lvalue_addr(node.operand)
            sz = ct ? (ct.size rescue 8) : 8
            old = new_temp; emit(Load.new(old, addr, ct, sz))
            new_val = new_temp
            if esz
              emit(Gep.new(new_val, old, Const.new(-1), esz))
            else
              emit(Binary.new(new_val, :minus, old, Const.new(1)))
            end
            new_val = maybe_truncate_narrow(new_val, ct) unless esz
            emit(Store.new(addr, new_val, nil, sz))
            old
          end
        else
          build_expr(node.operand)
        end
      end

      def build_assign(node)
        val = build_expr(node.value)

        # For compound assignment to a deref target (*ptr op= val), build the
        # pointer ONCE and reuse it for both the load and the store. Without
        # this, operands with side effects (e.g. *w++ += x) are evaluated
        # twice, advancing the pointer twice.
        saved_deref_ptr = nil
        saved_deref_esz = nil

        if node.op != :assign
          op  = node.op.to_s.sub('_assign', '').to_sym
          # Load old value from lvalue
          old = if node.target.is_a?(AST::UnaryOp) && node.target.op == :deref
                  saved_deref_esz = elem_size_for(node.target.operand.ctype)
                  saved_deref_ptr = build_expr(node.target.operand)
                  t = new_temp
                  emit(Load.new(t, saved_deref_ptr, node.target.ctype, saved_deref_esz))
                  t
                else
                  build_expr(node.target)
                end
          result = new_temp
          tct = node.target.ctype
          if pointer_ctype?(tct) && (op == :plus || op == :minus)
            esz = elem_size_for(tct)
            if op == :plus
              emit(Gep.new(result, old, val, esz))
            else
              neg = new_temp
              emit(Unary.new(neg, :neg, val))
              emit(Gep.new(result, old, neg, esz))
            end
          else
            # Apply unsigned variants for div/mod/rshift when target or rhs is unsigned.
            if %i[slash percent rshift].include?(op)
              rct = node.value.ctype
              if unsigned_ctype?(tct) || unsigned_ctype?(rct)
                op = { slash: :udiv, percent: :umod, rshift: :urshift }.fetch(op, op)
              end
            end
            emit(Binary.new(result, op, old, val))
          end
          val = result
          # Compound assignment to narrow integer types: the expression value must
          # be the stored (truncated) value, not the wide intermediate result.
          tct_inner = tct.respond_to?(:unqualified) ? tct.unqualified : tct
          if tct_inner.is_a?(OCC::Types::IntegerType) && tct_inner.size < 8
            trunc = new_temp
            emit(Cast.new(trunc, val, tct_inner.to_s, tct))
            val = trunc
          end
        end

        # Implicit integer → float/double conversion when assigning to an FP lvalue.
        if node.op == :assign
          tgt_ct = node.target.ctype
          val_ct  = node.value.ctype
          if fp_type?(tgt_ct) && val_ct && !fp_type?(val_ct) && !pointer_ctype?(val_ct)
            cast_t = new_temp
            emit(Cast.new(cast_t, val, val_ct, tgt_ct))
            val = cast_t
          end
          # Simple assignment to narrow integer types: the expression value must be
          # the stored (truncated) value, not the wide rhs (e.g. uint32_t = int64_t).
          tgt_inner = tgt_ct.respond_to?(:unqualified) ? tgt_ct.unqualified : tgt_ct
          if bool_type?(tgt_inner)
            val = cast_to_bool(val)
          elsif tgt_inner.is_a?(OCC::Types::IntegerType) && tgt_inner.size < 8
            trunc = new_temp
            emit(Cast.new(trunc, val, tgt_inner.to_s, tgt_inner))
            val = trunc
          end
        end

        # Store to lvalue
        case node.target
        when AST::Identifier
          slot = @locals[node.target.name]
          tgt_ct = node.target.ctype
          # If the target is a struct/union, pass its byte size so the codegen
          # knows to copy the struct bytes from the source address, not store
          # the source address itself.
          struct_sz = if tgt_ct.is_a?(OCC::Types::StructType) && tgt_ct.complete?
                        tgt_ct.size rescue nil
                      end
          esz = struct_sz || 8
          if slot
            emit(Store.new(slot, val, tgt_ct, esz))
          else
            emit(Store.new(GlobalRef.new(global_name_for(node.target.name)), val, tgt_ct, esz))
          end
        when AST::UnaryOp
          if node.target.op == :deref
            ptr     = saved_deref_ptr || build_expr(node.target.operand)
            elem_sz = saved_deref_esz || elem_size_for(node.target.operand.ctype)
            val_ct  = node.value.respond_to?(:ctype) ? node.value.ctype : nil
            # GlobalRef as ptr means a pointer stored in a global variable.
            # Use AddrOf+Load: load_operand(GlobalRef) already loads the global's
            # VALUE, so Load(GlobalRef) would double-dereference. Instead emit
            # AddrOf(addr, GlobalRef) then Load(t, addr) to read the pointer once.
            if ptr.is_a?(IR::GlobalRef) && @mod.globals.key?(ptr.name)
              addr = new_temp
              emit(AddrOf.new(addr, ptr))
              t = new_temp
              g_type = @mod.globals[ptr.name][:type]
              g_sz   = g_type.respond_to?(:size) ? (g_type.size rescue 8) : 8
              emit(Load.new(t, addr, g_type, g_sz))
              ptr = t
            end
            emit(Store.new(ptr, val, val_ct, elem_sz))
          end
        when AST::IndexExpr
          arr     = build_expr(node.target.array)
          idx     = build_expr(node.target.index)
          tgt_act = node.target.array.ctype || infer_node_ctype(node.target.array)
          elem_sz = elem_size_for(tgt_act)
          ptr     = new_temp
          emit(Gep.new(ptr, arr, idx, elem_sz))
          val_ct  = node.value.respond_to?(:ctype) ? node.value.ctype : nil
          emit(Store.new(ptr, val, val_ct, elem_sz))
        when AST::MemberExpr
          bf = bitfield_info(node.target)
          if bf
            # Read-modify-write into the storage unit
            unit_ptr = build_member_addr(node.target)
            old_unit = new_temp
            emit(Load.new(old_unit, unit_ptr, nil, bf[:unit_size]))
            mask        = (1 << bf[:bit_width]) - 1
            clear_mask  = ~(mask << bf[:bit_offset]) & 0xFFFF_FFFF_FFFF_FFFF
            cleared     = new_temp
            emit(Binary.new(cleared, :amp, old_unit, Const.new(clear_mask)))
            val_masked  = new_temp
            emit(Binary.new(val_masked, :amp, val, Const.new(mask)))
            val_shifted = new_temp
            emit(Binary.new(val_shifted, :lshift, val_masked, Const.new(bf[:bit_offset])))
            new_unit    = new_temp
            emit(Binary.new(new_unit, :pipe, cleared, val_shifted))
            emit(Store.new(unit_ptr, new_unit, nil, bf[:unit_size]))
          else
            field_ptr = build_member_addr(node.target)
            elem_sz   = member_field_size(node.target)
            val_ct    = node.value.respond_to?(:ctype) ? node.value.ctype : nil
            emit(Store.new(field_ptr, val, val_ct, elem_sz))
          end
        end

        val
      end

      def build_call(node)
        # Collect parameter types from the callee's function type for implicit conversions.
        callee_ft = node.callee.respond_to?(:ctype) ? node.callee.ctype : nil
        callee_ft = callee_ft.base if callee_ft.is_a?(Types::PointerType) && callee_ft.base.is_a?(Types::FunctionType)
        param_types = callee_ft.is_a?(Types::FunctionType) ? callee_ft.params : []

        args = node.args.each_with_index.flat_map do |a, i|
          param_ct = param_types[i]&.fetch(:type, nil) rescue nil
          arg_ct   = a.respond_to?(:ctype) ? a.ctype : nil
          # Emit an explicit int→float cast when the parameter expects a floating-point type.
          if param_ct.is_a?(Types::FloatingType) && arg_ct && !arg_ct.is_a?(Types::FloatingType)
            val = build_expr(a)
            cast_t = new_temp
            emit(Cast.new(cast_t, val, arg_ct, param_ct))
            [cast_t]
          else
            build_call_arg(a)
          end
        end
        dst  = new_temp
        func_ref = case node.callee
                   when AST::Identifier
                     # If the callee name resolves to a local (function pointer), load it.
                     # Otherwise treat it as a direct global function reference.
                     if @locals.key?(node.callee.name)
                       build_ident(node.callee)
                     else
                       GlobalRef.new(node.callee.name)
                     end
                   else build_expr(node.callee)
                   end
        emit(Call.new(dst, func_ref, args, node.ctype))
        dst
      end

      # Lower a single call argument into one or more flat IR operands. For
      # struct-by-value arguments up to 16 bytes, load each 8-byte half into
      # its own temp and pass them as consecutive arguments per AAPCS64.
      def build_call_arg(arg_node)
        ct = arg_node.respond_to?(:ctype) ? arg_node.ctype : nil
        if ct.is_a?(OCC::Types::StructType) && ct.complete? &&
           (sz = (ct.size rescue 0)) > 0 && sz <= 16
          addr  = build_expr(arg_node)
          slots = sz > 8 ? 2 : 1
          (0...slots).map do |i|
            t = new_temp
            if i.zero?
              emit(Load.new(t, addr))
            else
              gep = new_temp
              emit(Gep.new(gep, addr, Const.new(i), 8))
              emit(Load.new(t, gep))
            end
            t
          end
        else
          [build_expr(arg_node)]
        end
      end

      def build_ternary(node)
        cond_val    = build_expr(node.cond)
        then_block  = new_block(new_label('tern_then'))
        else_block  = new_block(new_label('tern_else'))
        merge_block = new_block(new_label('tern_merge'))
        result_slot = new_temp
        emit(Alloca.new(result_slot, 'int'))
        emit(CondJump.new(cond_val, then_block.label, else_block.label))

        switch_to(then_block)
        tv = build_expr(node.then_expr)
        emit(Store.new(result_slot, tv))
        jump_to(merge_block)

        switch_to(else_block)
        ev = build_expr(node.else_expr)
        emit(Store.new(result_slot, ev))
        jump_to(merge_block)

        switch_to(merge_block)
        dst = new_temp
        emit(Load.new(dst, result_slot))
        dst
      end

      def build_index(node)
        arr     = build_expr(node.array)
        idx     = build_expr(node.index)
        # When the semantic analyzer skips annotating sub-expressions inside
        # initializer lists, node.array.ctype may be nil. Fall back to inferring
        # the type from the identifier's global registration or @local_ctypes.
        array_ct  = node.array.ctype || infer_node_ctype(node.array)
        elem_sz   = elem_size_for(array_ct)
        # Infer the result type for this indexing (element of the array/pointer).
        result_ct = node.ctype || infer_index_result_ctype(array_ct)
        ptr       = new_temp
        emit(Gep.new(ptr, arr, idx, elem_sz))
        # If the indexed result is itself an aggregate (array or struct), do
        # not load through the pointer — the expression decays to its address.
        if result_ct.is_a?(OCC::Types::ArrayType) ||
           result_ct.is_a?(OCC::Types::StructType)
          return ptr
        end
        dst = new_temp
        emit(Load.new(dst, ptr, result_ct, elem_sz))
        dst
      end

      # Infer the ctype of a node when semantic analysis didn't annotate it.
      def infer_node_ctype(node)
        case node
        when AST::Identifier
          slot = @locals[node.name]
          slot ? @local_ctypes[node.name] : (@mod.globals[global_name_for(node.name)]&.dig(:type))
        when AST::IndexExpr
          parent_ct = node.ctype || infer_node_ctype(node.array)
          infer_index_result_ctype(parent_ct)
        when AST::MemberExpr
          # Infer the type of a member access (e.g. for const_addr_of of nested members).
          return nil if node.arrow
          parent_ct = node.expr.ctype || infer_node_ctype(node.expr)
          return nil unless parent_ct
          parent_ct = parent_ct.unqualified if parent_ct.respond_to?(:unqualified)
          # For pointer member access, unwrap pointer first.
          parent_ct = parent_ct.base if node.arrow && parent_ct.is_a?(OCC::Types::PointerType)
          return nil unless parent_ct.is_a?(OCC::Types::StructType) && parent_ct.complete?
          field = parent_ct.fields.find { |f| f[:name] == node.member }
          field&.dig(:type)
        end
      end

      # Return the element type when indexing into array_ct.
      def infer_index_result_ctype(array_ct)
        ct = array_ct.respond_to?(:unqualified) ? array_ct.unqualified : array_ct
        case ct
        when OCC::Types::ArrayType   then ct.element
        when OCC::Types::PointerType then ct.base
        end
      end

      # ── Member access ────────────────────────────────────────────────────────

      def member_container_ctype(node)
        ctype = node.expr.ctype
        return nil unless ctype
        if node.arrow
          ctype = OCC::Types::PointerType.new(ctype.element) if ctype.is_a?(OCC::Types::ArrayType)
          ctype = ctype.base if ctype.is_a?(OCC::Types::PointerType)
        end
        ctype = ctype.unqualified if ctype.respond_to?(:unqualified)
        ctype
      end

      # Returns an operand holding the address of the named field.
      def build_member_addr(node)
        struct_ctype = member_container_ctype(node)
        return Const.new(0) unless struct_ctype
        return Const.new(0) unless struct_ctype.is_a?(OCC::Types::StructType) && struct_ctype.complete?

        field = struct_ctype.fields.find { |f| f[:name] == node.member }
        return Const.new(0) unless field

        # Base pointer: for -> load the pointer value; for . take the address of the struct.
        base_ptr = node.arrow ? build_expr(node.expr) : lvalue_addr(node.expr)
        if node.arrow && base_ptr.is_a?(IR::GlobalRef) && @mod.globals.key?(base_ptr.name)
          addr = new_temp
          emit(AddrOf.new(addr, base_ptr))
          t = new_temp
          g_type = @mod.globals[base_ptr.name][:type]
          g_sz   = g_type.respond_to?(:size) ? (g_type.size rescue 8) : 8
          emit(Load.new(t, addr, g_type, g_sz))
          base_ptr = t
        end

        byte_off = field[:offset]
        # For packed bitfields, the load unit starts at group_byte + floor(bit_offset/8).
        byte_off += field[:bit_offset] / 8 if field[:bit_width]
        if byte_off.zero?
          base_ptr
        else
          t = new_temp
          emit(Binary.new(t, :plus, base_ptr, Const.new(byte_off)))
          t
        end
      rescue
        Const.new(0)
      end

      # Load a struct field value, handling bitfields.
      def build_member(node)
        bf = bitfield_info(node)
        if bf
          unit_ptr = build_member_addr(node)
          raw      = new_temp
          emit(Load.new(raw, unit_ptr, nil, bf[:unit_size]))
          # Shift right by bit_offset, mask to bit_width bits
          shifted = new_temp
          emit(Binary.new(shifted, :rshift, raw, Const.new(bf[:bit_offset])))
          mask    = (1 << bf[:bit_width]) - 1
          masked  = new_temp
          emit(Binary.new(masked, :amp, shifted, Const.new(mask)))
          if bf[:signed]
            # Sign-extend: shift left to place sign bit at bit 63, then arithmetic right shift
            shl_amt = 64 - bf[:bit_width]
            t1 = new_temp
            emit(Binary.new(t1, :lshift, masked, Const.new(shl_amt)))
            dst = new_temp
            emit(Binary.new(dst, :rshift, t1, Const.new(shl_amt)))
            dst
          else
            masked
          end
        else
          field_ptr = build_member_addr(node)
          # Array-type and struct/union-type fields return the address directly.
          # Struct rvalues are always represented as addresses in OCC IR (consistent
          # with build_deref for structs), so the Store small-struct-copy path can
          # dereference them correctly.
          if node.ctype.is_a?(OCC::Types::ArrayType) ||
             node.ctype.is_a?(OCC::Types::StructType)
            return field_ptr
          end
          elem_sz   = member_field_size(node)
          dst       = new_temp
          emit(Load.new(dst, field_ptr, node.ctype, elem_sz))
          dst
        end
      end

      # Emit a bitfield read-modify-write store: load the storage unit, clear the field
      # bits, insert the new value, and store the unit back.
      def emit_bitfield_rmw_store(member_node, bf, val)
        unit_ptr = build_member_addr(member_node)
        old_unit = new_temp
        emit(Load.new(old_unit, unit_ptr, nil, bf[:unit_size]))
        mask        = (1 << bf[:bit_width]) - 1
        clear_mask  = ~(mask << bf[:bit_offset]) & 0xFFFF_FFFF_FFFF_FFFF
        cleared     = new_temp
        emit(Binary.new(cleared, :amp, old_unit, Const.new(clear_mask)))
        val_masked  = new_temp
        emit(Binary.new(val_masked, :amp, val, Const.new(mask)))
        val_shifted = new_temp
        emit(Binary.new(val_shifted, :lshift, val_masked, Const.new(bf[:bit_offset])))
        new_unit    = new_temp
        emit(Binary.new(new_unit, :pipe, cleared, val_shifted))
        emit(Store.new(unit_ptr, new_unit, nil, bf[:unit_size]))
      end

      # Return bitfield metadata {bit_offset:, bit_width:, unit_size:, byte_start:, signed:} or nil.
      # Under #pragma pack, bit_offset can be ≥ 8, meaning the load must start
      # at group_byte + floor(bit_offset/8) with an adjusted bit position within
      # that aligned load unit.
      def bitfield_info(node)
        ctype = member_container_ctype(node)
        return nil unless ctype
        return nil unless ctype.is_a?(OCC::Types::StructType) && ctype.complete?
        field = ctype.fields.find { |f| f[:name] == node.member }
        return nil unless field && field[:bit_width]
        ft = field[:type]
        ft = ft.unqualified if ft.respond_to?(:unqualified)
        signed = ft.is_a?(OCC::Types::IntegerType) && ft.signed?
        raw_bit_offset = field[:bit_offset]
        bit_width      = field[:bit_width]
        # Byte start within the group: for packed bitfields bit_offset can be ≥ 8.
        byte_start     = raw_bit_offset / 8
        adj_bit_offset = raw_bit_offset % 8
        # Minimum power-of-2 load size that covers all the bits from adj_bit_offset.
        total_bits = adj_bit_offset + bit_width
        load_size  = total_bits <= 8 ? 1 : total_bits <= 16 ? 2 : total_bits <= 32 ? 4 : 8
        { bit_offset: adj_bit_offset, bit_width: bit_width,
          unit_size: load_size, byte_start: byte_start, signed: signed }
      rescue
        nil
      end

      # Return the byte size of a named field, or 8 on failure.
      def member_field_size(node)
        ctype = member_container_ctype(node)
        return 8 unless ctype
        return 8 unless ctype.is_a?(OCC::Types::StructType) && ctype.complete?
        field = ctype.fields.find { |f| f[:name] == node.member }
        field ? field[:type].size : 8
      rescue
        8
      end

      # Compute a pointer to the given lvalue expression without loading it.
      def lvalue_addr(node)
        dst = new_temp
        case node
        when AST::Identifier
          slot = @locals[node.name]
          if slot
            emit(AddrOf.new(dst, slot))
          else
            emit(AddrOf.new(dst, GlobalRef.new(global_name_for(node.name))))
          end
        when AST::UnaryOp
          if node.op == :deref
            result = build_expr(node.operand)
            # GlobalRef as ptr means a pointer stored in a global variable.
            # We need the VALUE stored in the global (the pointer) — not the
            # global's own address, and not a double-dereference.
            # Use AddrOf to get &global, then Load to read global's value.
            if result.is_a?(IR::GlobalRef) && @mod.globals.key?(result.name)
              addr = new_temp
              emit(AddrOf.new(addr, result))
              t = new_temp
              g_type = @mod.globals[result.name][:type]
              g_sz   = g_type.respond_to?(:size) ? (g_type.size rescue 8) : 8
              emit(Load.new(t, addr, g_type, g_sz))
              return t
            end
            return result
          end
          emit(Copy.new(dst, build_expr(node)))
        when AST::IndexExpr
          arr     = build_expr(node.array)
          idx     = build_expr(node.index)
          arr_act = node.array.ctype || infer_node_ctype(node.array)
          esz     = elem_size_for(arr_act)
          emit(Gep.new(dst, arr, idx, esz))
        when AST::MemberExpr
          return build_member_addr(node)
        else
          emit(Copy.new(dst, build_expr(node)))
        end
        dst
      end

      # Return element byte size for array/pointer type, defaulting to 8.
      def elem_size_for(ctype)
        return 8 unless ctype
        ct = ctype.respond_to?(:unqualified) ? ctype.unqualified : ctype
        case ct
        when OCC::Types::ArrayType   then ct.element.size
        when OCC::Types::PointerType then ct.base.size
        else 8
        end
      rescue
        8
      end

      def build_cast(node)
        # Compound literal: (type){ ... }
        if node.expr.is_a?(Hash) && node.expr[:kind] == :initializer_list
          ctype = node.ctype
          # For unsized array compound literals (T[]), infer count from the
          # initializer so that the Alloca reserves the correct amount of space.
          if ctype.is_a?(OCC::Types::ArrayType) && ctype.count.nil?
            items = node.expr[:items] || []
            ctype = OCC::Types::ArrayType.new(ctype.element, items.length)
          end
          slot  = new_temp
          emit(Alloca.new(slot, ctype || 'int'))
          addr = new_temp
          emit(AddrOf.new(addr, slot))
          build_initializer_list(addr, node.expr, ctype)
          return addr
        end

        src = build_expr(node.expr)
        dst = new_temp
        spec = node.type_spec.is_a?(Hash) ? node.type_spec[:specs] : node.type_spec
        type_name = spec.type_keywords.map(&:to_s).join(' ')
        emit(Cast.new(dst, src, type_name, node.ctype))
        dst
      end

      def build_sizeof_type(node)
        # sizeof_val is pre-computed by the semantic analyzer.
        return Const.new(node.sizeof_val) if node.sizeof_val
        # Fallback for cases the semantic analyzer didn't annotate.
        spec  = node.type_spec.is_a?(Hash) ? node.type_spec[:specs] : node.type_spec
        ctype = OCC::Types.from_specifiers(spec)
        Const.new(ctype.size)
      rescue StandardError
        Const.new(8)
      end

      def build_sizeof_expr(node)
        # sizeof_val is pre-computed by the semantic analyzer.
        return Const.new(node.sizeof_val) if node.sizeof_val
        # Fallback for literal-only cases.
        case node.operand
        when AST::CharLiteral   then Const.new(1)
        when AST::IntLiteral    then Const.new(4)
        when AST::FloatLiteral
          node.operand.suffix.to_s.downcase.include?('f') ? Const.new(4) : Const.new(8)
        when AST::StringLiteral then Const.new(8)  # pointer
        else Const.new(8)
        end
      end

      # Build IR for a GCC statement expression ({ ... }).
      # All statements in the body are emitted inline; the last expression
      # statement's value becomes the result of the entire expression.
      def build_stmt_expr(node)
        result = Const.new(0)
        node.body.items.each do |item|
          case item
          when AST::Declaration
            build_local_decl(item)
          when AST::ExprStmt
            result = item.expr ? build_expr(item.expr) : Const.new(0)
          else
            build_stmt(item)
            result = Const.new(0)
          end
        end
        result
      end
    end
  end
end
