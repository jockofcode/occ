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
      attr_accessor :variadic

      def initialize(name, params, return_type, variadic: false)
        @name        = name
        @params      = params   # [{name:, type:}]
        @return_type = return_type
        @variadic    = variadic
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
      attr_reader :functions, :globals, :strings, :variadic_funcs, :fp_funcs

      def initialize
        @functions     = []
        @globals       = {}   # name => {type:, init:}
        @strings       = []   # StringRef values
        @variadic_funcs = {}   # name => named_param_count
        @fp_funcs       = Set.new  # names of functions returning float/double
      end

      def add_function(f) = @functions << f
      def add_global(name, type, init = nil) = (@globals[name] = { type: type, init: init })
      def add_string(value) = StringRef.new(@strings.tap { @strings << value }.length - 1)
      def mark_variadic(name, named_count = 0) = (@variadic_funcs[name] = named_count)
      def mark_fp_func(name)  = @fp_funcs << name

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
        @mod          = Mod.new
        @func         = nil     # current Function
        @block        = nil     # current BasicBlock
        @temp_counter = 0
        @label_counter= 0
        @locals       = {}      # name => Alloca temp
        @break_target = nil
        @cont_target  = nil
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

        ret_type = fn.specifiers.type_keywords.first&.to_s || 'int'
        params   = (fn.params || { params: [] })[:params].map do |p|
          { name: p[:name], type: p[:specs]&.type_keywords&.first&.to_s || 'int' }
        end
        variadic = (fn.params || { variadic: false })[:variadic]

        @func = Function.new(fn.name, params, ret_type, variadic: variadic)
        @mod.add_function(@func)
        @mod.mark_variadic(fn.name, params.length) if variadic

        entry = new_block('entry')
        switch_to(entry)

        # Create alloca slots for each parameter.
        # Phase 1: capture all incoming register values into copy temps FIRST so
        # that later alloca/store work does not overwrite a register slot before
        # all registers have been read.
        param_copy_temps = params.each_with_index.filter_map do |p, idx|
          next unless p[:name]
          ct = new_temp
          emit(Copy.new(ct, Temp.new(idx)))
          [p, ct]
        end

        # Phase 2: alloca + store for each parameter
        param_copy_temps.each do |(p, ct)|
          slot = new_temp
          emit(Alloca.new(slot, p[:type]))
          emit(Store.new(slot, ct))
          @locals[p[:name]] = slot
        end

        build_stmt(fn.body)

        # Ensure all blocks are terminated
        emit(Return.new) unless @block.terminated?

        @func = nil
      end

      def build_global_decl(decl)
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
          type_sample = d[:type_fn]&.call(:base)
          next if type_sample.is_a?(Hash) && type_sample[:kind] == :function

          actual_type = begin
            d[:type_fn]&.call(base_type) || base_type
          rescue StandardError
            'int'
          end
          # Discard function-type results (shouldn't happen here, but be safe)
          actual_type = 'int' if actual_type.is_a?(Hash)

          init_val = d[:init] ? eval_const_init(d[:init]) : nil
          @mod.add_global(d[:name], actual_type, init_val)
        end
      end

      # Evaluate a simple constant initializer to an integer, or nil.
      def eval_const_init(expr)
        case expr
        when AST::IntLiteral  then expr.integer_value
        when AST::CharLiteral then expr.value.ord
        when AST::UnaryOp
          if expr.op == :unary_minus
            v = eval_const_init(expr.operand)
            v ? -v : nil
          end
        when AST::BinaryOp
          l = eval_const_init(expr.left)
          r = eval_const_init(expr.right)
          return nil unless l && r
          case expr.op
          when :plus  then l + r
          when :minus then l - r
          when :star  then l * r
          when :slash then r != 0 ? l / r : nil
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
        decl.declarators.each do |d|
          next unless d[:name]
          ctype = d[:resolved_type]
          slot  = new_temp
          emit(Alloca.new(slot, ctype || 'int'))
          @locals[d[:name]] = slot

          if d[:init]
            if d[:init].is_a?(Hash) && d[:init][:kind] == :initializer_list
              addr = new_temp
              emit(AddrOf.new(addr, slot))
              build_initializer_list(addr, d[:init], ctype)
            else
              val = build_expr(d[:init])
              emit(Store.new(slot, val))
            end
          end
        end
      end

      # Emit stores for a brace-enclosed initializer list into memory starting at base_ptr.
      def build_initializer_list(base_ptr, init_list, ctype)
        items = init_list[:items] || []
        return if items.empty?

        if ctype.is_a?(OCC::Types::StructType) && ctype.complete?
          items.each_with_index do |item, seq_idx|
            # Resolve target field (designated or sequential)
            field = if item[:designators]&.any? { |d| d[0] == :field }
                      fname = item[:designators].reverse.find { |d| d[0] == :field }&.last
                      ctype.fields.find { |f| f[:name] == fname }
                    else
                      ctype.fields[seq_idx]
                    end
            next unless field && item[:value]
            val    = build_expr(item[:value])
            esz    = field[:type].size rescue 8
            if field[:offset].zero?
              emit(Store.new(base_ptr, val, nil, esz))
            else
              fptr = new_temp
              emit(Binary.new(fptr, :plus, base_ptr, Const.new(field[:offset])))
              emit(Store.new(fptr, val, nil, esz))
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
            val  = build_expr(item[:value])
            eptr = new_temp
            emit(Gep.new(eptr, base_ptr, idx, esz))
            emit(Store.new(eptr, val, nil, esz))
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

        # First pass: collect case values and create blocks for each case/default
        case_map      = {}   # integer_value => BasicBlock
        default_block = nil

        items.each do |item|
          case item
          when AST::CaseStmt
            val = eval_case_value(item.value)
            next if val.nil? || case_map.key?(val)
            case_map[val] = new_block(new_label('switch_case'))
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
        when AST::CharLiteral then expr.value.ord
        when AST::UnaryOp
          if expr.op == :unary_minus
            v = eval_case_value(expr.operand)
            v ? -v : nil
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
        when AST::CharLiteral   then Const.new(node.value.ord)
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
        else
          Const.new(0)
        end
      end

      def build_ident(node)
        slot = @locals[node.name]
        if slot
          # Arrays decay to a pointer to their first element.
          if node.ctype.is_a?(OCC::Types::ArrayType)
            t = new_temp
            emit(AddrOf.new(t, slot))
            t
          else
            t = new_temp
            emit(Load.new(t, slot, node.ctype))
            t
          end
        else
          # Global variable. Arrays and structs used in expressions yield their address.
          if node.ctype.is_a?(OCC::Types::ArrayType)
            t = new_temp
            emit(AddrOf.new(t, GlobalRef.new(node.name)))
            t
          else
            GlobalRef.new(node.name)
          end
        end
      end

      def build_binop(node)
        left  = build_expr(node.left)
        right = build_expr(node.right)
        dst   = new_temp
        emit(Binary.new(dst, node.op, left, right, node.ctype))
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
              emit(AddrOf.new(dst, GlobalRef.new(node.operand.name)))
            end
          else
            emit(Copy.new(dst, build_expr(node.operand)))
          end
          dst
        when :deref
          ptr = build_expr(node.operand)
          elem_sz = elem_size_for(node.operand.ctype)
          dst = new_temp
          emit(Load.new(dst, ptr, nil, elem_sz))
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
          dst
        when :pre_inc
          slot = @locals[node.operand.name] if node.operand.is_a?(AST::Identifier)
          if slot
            old = new_temp; emit(Load.new(old, slot))
            one = Const.new(1)
            new_val = new_temp; emit(Binary.new(new_val, :plus, old, one))
            emit(Store.new(slot, new_val))
            new_val
          else
            build_expr(node.operand)
          end
        when :post_inc
          slot = @locals[node.operand.name] if node.operand.is_a?(AST::Identifier)
          if slot
            old = new_temp; emit(Load.new(old, slot))
            one = Const.new(1)
            new_val = new_temp; emit(Binary.new(new_val, :plus, old, one))
            emit(Store.new(slot, new_val))
            old   # return old value
          else
            build_expr(node.operand)
          end
        when :pre_dec
          slot = @locals[node.operand.name] if node.operand.is_a?(AST::Identifier)
          if slot
            old = new_temp; emit(Load.new(old, slot))
            one = Const.new(1)
            new_val = new_temp; emit(Binary.new(new_val, :minus, old, one))
            emit(Store.new(slot, new_val))
            new_val
          else
            build_expr(node.operand)
          end
        when :post_dec
          slot = @locals[node.operand.name] if node.operand.is_a?(AST::Identifier)
          if slot
            old = new_temp; emit(Load.new(old, slot))
            one = Const.new(1)
            new_val = new_temp; emit(Binary.new(new_val, :minus, old, one))
            emit(Store.new(slot, new_val))
            old
          else
            build_expr(node.operand)
          end
        else
          build_expr(node.operand)
        end
      end

      def build_assign(node)
        val = build_expr(node.value)

        if node.op != :assign
          # Compound assignment: load, op, store
          old = build_expr(node.target)
          op  = node.op.to_s.sub('_assign', '').to_sym
          result = new_temp
          emit(Binary.new(result, op, old, val))
          val = result
        end

        # Store to lvalue
        case node.target
        when AST::Identifier
          slot = @locals[node.target.name]
          if slot
            emit(Store.new(slot, val))
          else
            emit(Store.new(GlobalRef.new(node.target.name), val))
          end
        when AST::UnaryOp
          if node.target.op == :deref
            ptr = build_expr(node.target.operand)
            elem_sz = elem_size_for(node.target.operand.ctype)
            emit(Store.new(ptr, val, nil, elem_sz))
          end
        when AST::IndexExpr
          arr    = build_expr(node.target.array)
          idx    = build_expr(node.target.index)
          elem_sz = elem_size_for(node.target.array.ctype)
          ptr    = new_temp
          emit(Gep.new(ptr, arr, idx, elem_sz))
          emit(Store.new(ptr, val, nil, elem_sz))
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
        args = node.args.map { |a| build_expr(a) }
        dst  = new_temp
        func_ref = case node.callee
                   when AST::Identifier then GlobalRef.new(node.callee.name)
                   else build_expr(node.callee)
                   end
        emit(Call.new(dst, func_ref, args, node.ctype))
        dst
      end

      def build_ternary(node)
        cond_val    = build_expr(node.cond)
        then_block  = new_block('tern_then')
        else_block  = new_block('tern_else')
        merge_block = new_block('tern_merge')
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
        dst = new_temp
        emit(Load.new(dst, ptr, nil, elem_sz))
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
          elem_sz   = member_field_size(node)
          dst       = new_temp
          emit(Load.new(dst, field_ptr, nil, elem_sz))
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
            emit(AddrOf.new(dst, GlobalRef.new(node.name)))
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
        spec  = node.type_spec.is_a?(Hash) ? node.type_spec[:specs] : node.type_spec
        ctype = OCC::Types.from_specifiers(spec)
        Const.new(ctype.size)
      rescue
        Const.new(8)
      end

      def build_sizeof_expr(node)
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
