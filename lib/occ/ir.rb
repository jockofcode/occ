# frozen_string_literal: true

module OCC
  module IR
    # ── Instructions ───────────────────────────────────────────────────────────

    # An operand is either a Temp, a Const, or a GlobalRef.
    Temp      = Struct.new(:id)    { def to_s = "%#{id}" }
    Const     = Struct.new(:value) { def to_s = value.to_s }
    GlobalRef = Struct.new(:name)  { def to_s = "@#{name}" }
    StringRef = Struct.new(:id)    { def to_s = "str_#{id}" }

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
      def terminated? = @instrs.last.is_a?(Jump) || @instrs.last.is_a?(CondJump) || @instrs.last.is_a?(Return)

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
      attr_reader :functions, :globals, :strings, :variadic_funcs, :fp_funcs, :func_names,
                  :defined_funcs

      def initialize
        @functions     = []
        @globals       = {}         # name => {type:, init:}
        @strings       = []         # StringRef values
        @variadic_funcs = {}        # name => named_param_count
        @fp_funcs       = Set.new   # names of functions returning float/double
        @func_names     = Set.new   # all known function names (defined or declared extern)
        @defined_funcs  = Set.new   # functions with a body in this translation unit
      end

      def add_function(f)
        @functions << f
        @func_names << f.name
        @defined_funcs << f.name
      end
      def add_global(name, type, init = nil) = (@globals[name] = { type: type, init: init })
      def add_string(value) = StringRef.new(@strings.tap { @strings << value }.length - 1)
      def mark_variadic(name, named_count = 0) = (@variadic_funcs[name] = named_count)
      def mark_fp_func(name)  = @fp_funcs << name
      def mark_func(name)     = @func_names << name

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
        @break_target    = nil
        @cont_target     = nil
        @enum_constants  = {}      # name => Integer (compile-time enum values)
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

      # ── External declarations ────────────────────────────────────────────────

      def build_external(node)
        case node
        when AST::FunctionDef  then build_function(node)
        when AST::Declaration  then build_global_decl(node)
        end
      end

      def build_function(fn)
        @temp_counter  = 0
        @label_counter = 0
        @locals        = {}
        @local_ctypes  = {}
        @static_locals = {}

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

        is_static = fn.specifiers.storage == :static
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
            emit(Store.new(slot, cts.first))
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

      def build_global_decl(decl)
        # Collect enum constants from inline enum definitions.
        tag_decl = decl.specifiers.tag_decl
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
        end

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
          if type_sample.is_a?(Hash) && type_sample[:kind] == :function
            full_type = d[:type_fn]&.call(base_type) rescue nil
            if full_type.is_a?(Hash) && full_type[:kind] == :function
              params = full_type[:params]
              if params.is_a?(Hash) && params[:variadic]
                named_count = params[:params]&.length || 0
                @mod.mark_variadic(d[:name], named_count)
              end
              ret = full_type[:return]
              @mod.mark_fp_func(d[:name]) if ret.is_a?(OCC::Types::FloatingType)
              @mod.mark_func(d[:name])
            end
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

          init_val = d[:init] ? eval_const_init(d[:init], allow_ref: true) : nil
          @mod.add_global(d[:name], actual_type, init_val)
        end
      end

      # Evaluate a simple constant initializer.
      # Returns Integer, Float, { kind: :string, value: "..." }, { kind: :ref, name: "..." },
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
        when AST::Identifier
          if @enum_constants.key?(expr.name)
            @enum_constants[expr.name]
          elsif allow_ref
            { kind: :ref, name: expr.name }
          end
        when AST::Cast
          eval_const_init(expr.expr, allow_ref: allow_ref)
        when AST::UnaryOp
          v = eval_const_init(expr.operand, allow_ref: allow_ref)
          case expr.op
          when :unary_minus then v.is_a?(Numeric) ? -v : nil
          when :bit_not     then v.is_a?(Integer) ? ~v : nil
          else nil
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
          when :lshift then l << r
          when :rshift then l >> r
          when :amp    then l & r
          when :pipe   then l | r
          when :caret  then l ^ r
          end
        when Hash
          if expr[:kind] == :initializer_list
            { kind: :initializer_list,
              items: (expr[:items] || []).map { |item| eval_const_init(item[:value], allow_ref: true) } }
          end
        else nil
        end
      end

      # ── Statement builders ──────────────────────────────────────────────────

      def build_stmt(node)
        case node
        when AST::CompoundStmt  then node.items.each { |item| build_block_item(item) }
        when AST::ExprStmt      then build_expr(node.expr) if node.expr
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
        when AST::CaseStmt, AST::DefaultStmt
          # handled by switch builder; just emit the nested stmt
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
        # Collect enum constants from inline enum definitions (may appear locally).
        tag_decl = decl.specifiers.tag_decl
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
        end

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
            mangled = "__static_#{@func.name}_#{d[:name]}"
            init_val = d[:init] ? eval_const_init(d[:init], allow_ref: true) : nil
            @mod.add_global(mangled, ctype || 'int', init_val)
            @static_locals[d[:name]] = mangled
            @local_ctypes[d[:name]] = ctype if ctype
            next
          end

          slot  = new_temp
          emit(Alloca.new(slot, ctype || 'int'))
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
              emit(Store.new(slot, val))
            end
          end
        end
      end

      # Resolve an identifier name to the actual storage name. For static locals
      # this returns the mangled global name; otherwise it returns the name as-is.
      def global_name_for(name)
        @static_locals[name] || name
      end

      # Emit stores for a brace-enclosed initializer list into memory starting at base_ptr.
      def build_initializer_list(base_ptr, init_list, ctype)
        items = init_list[:items] || []

        if ctype.is_a?(OCC::Types::StructType) && ctype.complete?
          # Zero-initialize all fields first (C11 §6.7.9 ¶10: unspecified members are zero)
          ctype.fields.each do |field|
            next unless field[:name]
            fptr = if field[:offset].zero?
                     base_ptr
                   else
                     t = new_temp
                     emit(Binary.new(t, :plus, base_ptr, Const.new(field[:offset])))
                     t
                   end
            esz = field[:type].size rescue 8
            emit(Store.new(fptr, Const.new(0), field[:type], esz))
          end
          # Then apply explicit initializers
          items.each_with_index do |item, seq_idx|
            # Resolve target field (designated or sequential)
            field = if item[:designators]&.any? { |d| d[0] == :field }
                      fname = item[:designators].reverse.find { |d| d[0] == :field }&.last
                      ctype.fields.find { |f| f[:name] == fname }
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
            if item[:value].is_a?(Hash) && item[:value][:kind] == :initializer_list
              build_initializer_list(fptr, item[:value], field[:type])
            else
              val = build_expr(item[:value])
              esz = field[:type].size rescue 8
              emit(Store.new(fptr, val, field[:type], esz))
            end
          end
        elsif ctype.is_a?(OCC::Types::ArrayType)
          elem_ct = ctype.element
          esz     = elem_ct.size rescue 8
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

      def build_return(node)
        if node.value
          val = build_expr(node.value)
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

      def build_switch(node)
        switch_val  = build_expr(node.expr)
        saved_break = @break_target

        items = node.body.is_a?(AST::CompoundStmt) ? node.body.items : [node.body]

        # First pass: collect case values and create blocks for each case/default.
        # Fall-through cases (case A: case B: body) are nested CaseStmts in our AST;
        # all values in a chain share one block so the dispatch works correctly.
        case_map      = {}   # integer_value => BasicBlock
        default_block = nil

        items.each do |item|
          case item
          when AST::CaseStmt
            # Walk the nested CaseStmt chain, collecting all case values.
            chain_vals = []
            s = item
            while s.is_a?(AST::CaseStmt)
              v = eval_case_value(s.value)
              chain_vals << v if v && !case_map.key?(v)
              s = s.stmt
            end
            # All values in this chain share one block.
            blk = new_block(new_label('switch_case'))
            chain_vals.each { |v| case_map[v] = blk }
          when AST::DefaultStmt
            default_block ||= new_block(new_label('switch_default'))
          end
        end

        end_block     = new_block(new_label('switch_end'))
        @break_target = end_block.label

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
        # Fall-through: if a case block is not terminated when the next case is reached,
        # jump_to emits an explicit Jump to the next case block.
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
            build_stmt(item)
          end
        end

        jump_to(end_block) unless @block&.terminated?
        switch_to(end_block)
        @break_target = saved_break
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
        # Use unsigned variants when either operand is an unsigned integer type.
        # FP types never use unsigned comparison variants (float has no signed/unsigned).
        if %i[gt lt geq leq slash percent rshift].include?(op)
          lct = node.left.ctype
          rct = node.right.ctype
          lct_inner = lct.respond_to?(:unqualified) ? lct.unqualified : lct
          rct_inner = rct.respond_to?(:unqualified) ? rct.unqualified : rct
          fp_compare = lct_inner.is_a?(OCC::Types::FloatingType) ||
                       rct_inner.is_a?(OCC::Types::FloatingType)
          unless fp_compare
            unsigned = unsigned_ctype?(lct) || unsigned_ctype?(rct) ||
                       (pointer_ctype?(lct) && pointer_ctype?(rct))
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
            arr = build_expr(node.operand.array)
            idx = build_expr(node.operand.index)
            esz = elem_size_for(node.operand.array.ctype)
            emit(Gep.new(dst, arr, idx, esz))
          when AST::MemberExpr
            return build_member_addr(node.operand)
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
            emit(Store.new(slot, new_val))
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
            emit(Store.new(slot, new_val))
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
            emit(Store.new(slot, new_val))
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
            emit(Store.new(slot, new_val))
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
            emit(Store.new(ptr, val, val_ct, elem_sz))
          end
        when AST::IndexExpr
          arr    = build_expr(node.target.array)
          idx    = build_expr(node.target.index)
          elem_sz = elem_size_for(node.target.array.ctype)
          ptr    = new_temp
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
            emit(Store.new(field_ptr, val, nil, elem_sz))
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
        elem_sz = elem_size_for(node.array.ctype)
        ptr     = new_temp
        emit(Gep.new(ptr, arr, idx, elem_sz))
        # If the indexed result is itself an aggregate (array or struct), do
        # not load through the pointer — the expression decays to its address.
        if node.ctype.is_a?(OCC::Types::ArrayType) ||
           node.ctype.is_a?(OCC::Types::StructType)
          return ptr
        end
        dst = new_temp
        emit(Load.new(dst, ptr, node.ctype, elem_sz))
        dst
      end

      # ── Member access ────────────────────────────────────────────────────────

      # Returns an operand holding the address of the named field.
      def build_member_addr(node)
        struct_ctype = node.expr.ctype
        return Const.new(0) unless struct_ctype

        # For ->, dereference the pointer to get the struct type.
        if node.arrow
          struct_ctype = struct_ctype.base if struct_ctype.is_a?(OCC::Types::PointerType)
        end
        struct_ctype = struct_ctype.unqualified if struct_ctype.respond_to?(:unqualified)
        return Const.new(0) unless struct_ctype.is_a?(OCC::Types::StructType) && struct_ctype.complete?

        field = struct_ctype.fields.find { |f| f[:name] == node.member }
        return Const.new(0) unless field

        # Base pointer: for -> load the pointer value; for . take the address of the struct.
        base_ptr = node.arrow ? build_expr(node.expr) : lvalue_addr(node.expr)

        if field[:offset].zero?
          base_ptr
        else
          t = new_temp
          emit(Binary.new(t, :plus, base_ptr, Const.new(field[:offset])))
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
          dst     = new_temp
          emit(Binary.new(dst, :amp, shifted, Const.new(mask)))
          dst
        else
          field_ptr = build_member_addr(node)
          # Array-type fields decay to a pointer to their first element — return
          # the address directly instead of loading through it.
          if node.ctype.is_a?(OCC::Types::ArrayType)
            return field_ptr
          end
          elem_sz   = member_field_size(node)
          dst       = new_temp
          emit(Load.new(dst, field_ptr, node.ctype, elem_sz))
          dst
        end
      end

      # Return bitfield metadata {bit_offset:, bit_width:, unit_size:} or nil.
      def bitfield_info(node)
        ctype = node.expr.ctype
        return nil unless ctype
        ctype = ctype.base if node.arrow && ctype.is_a?(OCC::Types::PointerType)
        ctype = ctype.unqualified if ctype.respond_to?(:unqualified)
        return nil unless ctype.is_a?(OCC::Types::StructType) && ctype.complete?
        field = ctype.fields.find { |f| f[:name] == node.member }
        return nil unless field && field[:bit_width]
        { bit_offset: field[:bit_offset], bit_width: field[:bit_width],
          unit_size: field[:unit_size] || 4 }
      rescue
        nil
      end

      # Return the byte size of a named field, or 8 on failure.
      def member_field_size(node)
        ctype = node.expr.ctype
        return 8 unless ctype
        ctype = ctype.base if node.arrow && ctype.is_a?(OCC::Types::PointerType)
        ctype = ctype.unqualified if ctype.respond_to?(:unqualified)
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
          return build_expr(node.operand) if node.op == :deref
          emit(Copy.new(dst, build_expr(node)))
        when AST::IndexExpr
          arr    = build_expr(node.array)
          idx    = build_expr(node.index)
          esz    = elem_size_for(node.array.ctype)
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
    end
  end
end
