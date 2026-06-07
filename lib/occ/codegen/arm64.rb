# frozen_string_literal: true

module OCC
  module Codegen
    # AArch64 (ARM64) code generator targeting macOS (Apple Silicon).
    # Follows the Apple AArch64 ABI.
    #
    # Calling convention:
    #   Integer args:  x0–x7
    #   FP args:       d0–d7  (independent from integer args)
    #   Return:        x0 (int) or d0 (fp)
    #   Frame ptr:     x29 (fp)
    #   Link reg:      x30 (lr)
    #   Scratch:       x9–x15, d9–d15
    #
    # All temporaries are spilled to the stack for simplicity.
    class ARM64 < Base
      ARG_REGS = %w[x0 x1 x2 x3 x4 x5 x6 x7].freeze

      def initialize(mod, target: :arm64_macos)
        super(mod)
        @target = target
      end

      private

      # macOS: symbols prefixed with underscore
      def sym(name) = "_#{name}"

      # ── Sections / preamble ──────────────────────────────────────────────────

      def emit_preamble
        emit '.section __TEXT,__text,regular,pure_instructions'
      end

      def emit_string_constant(id, value)
        emit '.section __TEXT,__cstring,cstring_literals'
        emit "l_str_#{id}:"
        emit "  .asciz #{value.inspect}"
        emit '.section __TEXT,__text,regular,pure_instructions'
        emit_blank
      end

      def emit_global(name, g)
        if g[:init]
          emit '.section __DATA,__data'
          emit ".globl #{sym(name)}"
          emit '.p2align 3'
          emit "#{sym(name)}:"
          emit "  .quad #{g[:init]}"
          emit '.section __TEXT,__text,regular,pure_instructions'
        else
          size = type_byte_size(g[:type])
          emit ".comm #{sym(name)},#{size},3"
        end
      end

      def type_byte_size(type)
        return type.size if type.respond_to?(:size)
        8
      rescue StandardError
        8
      end

      # ── Function ─────────────────────────────────────────────────────────────

      def emit_function(func)
        @func          = func
        @slot_map      = {}
        @slot_next     = 0    # bytes used so far for locals (x29+16 is first slot)
        @alloca_slots  = Set.new  # temp IDs that are direct alloca stack slots
        @alloca_sizes  = {}       # temp_id => actual byte size (for arrays/structs)
        @fp_alloca_slots = Set.new # alloca slots holding fp values
        @fp_temps      = Set.new  # temp IDs that hold fp (double/float) values
        @float_pool    = []   # [{label:, value:}] for literal-pool fp constants

        # Pre-scan: collect alloca temps, their sizes, and mark FP allocas
        alloca_extra = 0  # extra bytes beyond 8 for oversized alloca temps
        func.blocks.each do |bb|
          bb.instrs.each do |i|
            next unless i.is_a?(IR::Alloca)
            @alloca_slots << i.dst.id
            sz = ctype_stack_size(i.ctype)
            @alloca_sizes[i.dst.id] = sz
            alloca_extra += [sz - 8, 0].max
            @fp_alloca_slots << i.dst.id if fp_ctype?(i.ctype)
          end
        end

        # Type-propagation pass to identify FP-valued temps
        compute_fp_temps(func)

        # Compute frame size accounting for oversized alloca slots (arrays, structs)
        all_temps_count = collect_temp_count(func)
        @frame_sz = align16(all_temps_count * 8 + alloca_extra + 16)   # +16 for fp/lr pair
        frame_sz = @frame_sz

        name = sym(func.name)
        emit ".globl #{name}"
        emit '.p2align 2'
        emit "#{name}:"

        # Prologue: save fp and lr, set up frame pointer.
        # stp pre-index immediate is limited to [-512, 504]; use sub+stp for large frames.
        if frame_sz <= 504
          emit "  stp x29, x30, [sp, #-#{frame_sz}]!"
          emit '  mov x29, sp'
        else
          emit "  sub sp, sp, ##{frame_sz}"
          emit '  stp x29, x30, [sp]'
          emit '  mov x29, sp'
        end

        # Save incoming parameters — integer args in x0-x7, FP args in d0-d7
        int_idx = 0
        fp_idx  = 0
        func.params.each_with_index do |p, idx|
          next unless p[:name]
          slot = alloc_slot_for(IR::Temp.new(idx))
          if fp_ctype?(p[:type])
            emit "  str d#{fp_idx}, [x29, ##{slot}]"
            fp_idx += 1
          elsif int_idx < ARG_REGS.length
            emit "  str #{ARG_REGS[int_idx]}, [x29, ##{slot}]"
            int_idx += 1
          end
        end

        func.blocks.each { |bb| emit_block(bb) }

        # Float literal pool (per-function, placed after the function body)
        unless @float_pool.empty?
          emit '.p2align 3'
          @float_pool.each do |entry|
            emit "#{entry[:label]}:"
            emit "  .double #{entry[:value]}"
          end
        end

        emit_blank
      end

      # ── Basic block ──────────────────────────────────────────────────────────

      def emit_block(bb)
        emit "#{func_local(bb.label)}:"
        bb.instrs.each { |i| emit_instr(i) }
      end

      def func_local(label) = "L#{@func.name}_#{label}"

      # ── FP helpers ───────────────────────────────────────────────────────────

      def fp_ctype?(ct)
        ct.is_a?(OCC::Types::FloatingType) ||
          (ct.respond_to?(:unqualified) && ct.unqualified.is_a?(OCC::Types::FloatingType)) ||
          ct.to_s =~ /\A(double|float|long double)\z/
      end

      def fp_temp?(op)
        op.is_a?(IR::Temp) && @fp_temps.include?(op.id)
      end

      def fp_operand?(op)
        fp_temp?(op) || (op.is_a?(IR::Const) && op.value.is_a?(Float))
      end

      # Build the FP-temp set via dataflow over all blocks.
      def compute_fp_temps(func)
        changed = true
        while changed
          changed = false
          func.blocks.each do |bb|
            bb.instrs.each do |i|
              next unless i.respond_to?(:dst)
              next if @fp_temps.include?(i.dst.id)
              fp = case i
                   when IR::Copy
                     (i.src.is_a?(IR::Const) && i.src.value.is_a?(Float)) ||
                       fp_temp?(i.src)
                   when IR::Load
                     # FP if loaded from an FP alloca slot, or type annotation says FP
                     (i.ptr.is_a?(IR::Temp) && @fp_alloca_slots.include?(i.ptr.id)) ||
                       fp_ctype?(i.type)
                   when IR::Binary
                     fp_operand?(i.left) || fp_operand?(i.right) ||
                       fp_ctype?(i.type)
                   when IR::Call
                     name = i.func.is_a?(IR::GlobalRef) ? i.func.name : nil
                     (name && @mod.fp_funcs.include?(name)) || fp_ctype?(i.type)
                   when IR::Cast
                     fp_ctype?(i.type) ||
                       (i.to_type.is_a?(String) && i.to_type =~ /float|double/)
                   else
                     false
                   end
              if fp
                @fp_temps << i.dst.id
                changed = true
              end
            end
          end
        end
      end

      # Load an FP operand into an FP register (dreg).
      def load_fp_operand(op, dreg)
        case op
        when IR::Const
          val = op.value.to_f
          pool_id = @float_pool.length
          label   = "Lflt_#{@func.name}_#{pool_id}"
          @float_pool << { label: label, value: val }
          emit "  ldr #{dreg}, #{label}"
        when IR::Temp
          slot = slot_of(op)
          emit "  ldr #{dreg}, [x29, ##{slot}]"
        when IR::GlobalRef
          emit "  adrp x9, #{sym(op.name)}@PAGE"
          emit "  ldr  #{dreg}, [x9, #{sym(op.name)}@PAGEOFF]"
        end
      end

      # Store an FP register (dreg) to a temp's stack slot and mark it FP.
      def store_fp_temp(temp, dreg)
        slot = alloc_slot_for(temp)
        emit "  str #{dreg}, [x29, ##{slot}]"
        @fp_temps << temp.id
      end

      # ── Instruction emission ─────────────────────────────────────────────────

      def emit_instr(instr) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
        case instr
        when IR::Alloca
          alloc_slot_for(instr.dst)

        when IR::Copy
          if fp_operand?(instr.src)
            load_fp_operand(instr.src, 'd9')
            store_fp_temp(instr.dst, 'd9')
          else
            load_operand(instr.src, 'x9')
            store_temp(instr.dst, 'x9')
          end

        when IR::Load
          if instr.ptr.is_a?(IR::Temp) && @alloca_slots.include?(instr.ptr.id)
            if @fp_alloca_slots.include?(instr.ptr.id)
              emit "  ldr d10, [x29, ##{slot_of(instr.ptr)}]"
              store_fp_temp(instr.dst, 'd10')
            else
              emit "  ldr x10, [x29, ##{slot_of(instr.ptr)}]"
              store_temp(instr.dst, 'x10')
            end
          else
            load_operand(instr.ptr, 'x9')
            signed = instr.type.is_a?(OCC::Types::IntegerType) && instr.type.signed?
            case instr.elem_size
            when 1 then emit(signed ? '  ldrsb x10, [x9]' : '  ldrb w10, [x9]')
            when 2 then emit(signed ? '  ldrsh x10, [x9]' : '  ldrh w10, [x9]')
            when 4 then emit(signed ? '  ldrsw x10, [x9]' : '  ldr w10, [x9]')
            else        emit '  ldr x10, [x9]'
            end
            store_temp(instr.dst, 'x10')
          end

        when IR::Store
          if instr.ptr.is_a?(IR::Temp) && @alloca_slots.include?(instr.ptr.id)
            if @fp_alloca_slots.include?(instr.ptr.id) || fp_operand?(instr.value)
              load_fp_operand(instr.value, 'd9')
              emit "  str d9, [x29, ##{slot_of(instr.ptr)}]"
              @fp_alloca_slots << instr.ptr.id  # mark slot as FP once we store FP into it
            else
              load_operand(instr.value, 'x9')
              emit "  str x9, [x29, ##{slot_of(instr.ptr)}]"
            end
          else
            load_operand(instr.value, 'x9')
            case instr.ptr
            when IR::Temp
              ptr_slot = slot_of(instr.ptr)
              emit "  ldr x10, [x29, ##{ptr_slot}]"
              case instr.elem_size
              when 1 then emit '  strb w9, [x10]'
              when 2 then emit '  strh w9, [x10]'
              when 4 then emit '  str w9, [x10]'
              else        emit '  str x9, [x10]'
              end
            when IR::GlobalRef
              emit "  adrp x10, #{sym(instr.ptr.name)}@PAGE"
              emit "  add  x10, x10, #{sym(instr.ptr.name)}@PAGEOFF"
              case instr.elem_size
              when 1 then emit '  strb w9, [x10]'
              when 2 then emit '  strh w9, [x10]'
              when 4 then emit '  str w9, [x10]'
              else        emit '  str x9, [x10]'
              end
            end
          end

        when IR::AddrOf
          case instr.src
          when IR::Temp
            emit "  add x9, x29, ##{slot_of(instr.src)}"
          when IR::GlobalRef
            emit "  adrp x9, #{sym(instr.src.name)}@PAGE"
            emit "  add  x9, x9, #{sym(instr.src.name)}@PAGEOFF"
          end
          store_temp(instr.dst, 'x9')

        when IR::Gep
          load_operand(instr.ptr,   'x9')
          load_operand(instr.index, 'x10')
          esz = instr.elem_size
          if esz > 1
            log2 = Math.log2(esz)
            if log2 == log2.floor
              emit "  lsl x10, x10, ##{log2.to_i}"
            else
              emit "  mov x11, ##{esz}"
              emit "  mul x10, x10, x11"
            end
          end
          emit '  add x9, x9, x10'
          store_temp(instr.dst, 'x9')

        when IR::Unary
          load_operand(instr.src, 'x9')
          case instr.op
          when :neg
            emit '  neg x9, x9'
          when :not
            emit '  cmp x9, #0'
            emit '  cset x9, eq'
          when :bitnot
            emit '  mvn x9, x9'
          end
          store_temp(instr.dst, 'x9')

        when IR::Binary
          if fp_operand?(instr.left) || fp_operand?(instr.right) || fp_ctype?(instr.type)
            emit_fp_binary(instr)
          else
            emit_binary(instr)
          end

        when IR::Call
          emit_call(instr)

        when IR::Jump
          emit "  b #{func_local(instr.target)}"

        when IR::CondJump
          load_operand(instr.cond, 'x9')
          emit "  cbnz x9, #{func_local(instr.true_label)}"
          emit "  b    #{func_local(instr.false_label)}"

        when IR::Return
          if instr.value
            if fp_operand?(instr.value)
              load_fp_operand(instr.value, 'd0')
            else
              load_operand(instr.value, 'x0')
            end
          end
          # Epilogue
          frame_sz = @frame_sz
          if frame_sz <= 504
            emit "  ldp x29, x30, [sp], ##{frame_sz}"
          else
            emit '  ldp x29, x30, [sp]'
            emit "  add sp, sp, ##{frame_sz}"
          end
          emit '  ret'

        when IR::Cast
          if fp_operand?(instr.src) && !fp_ctype?(instr.type)
            # FP → integer truncation
            load_fp_operand(instr.src, 'd9')
            emit '  fcvtzs x9, d9'
            store_temp(instr.dst, 'x9')
          elsif !fp_operand?(instr.src) && fp_ctype?(instr.type)
            # integer → FP conversion
            load_operand(instr.src, 'x9')
            emit '  scvtf d9, x9'
            store_fp_temp(instr.dst, 'd9')
          else
            load_operand(instr.src, 'x9')
            store_temp(instr.dst, 'x9')
          end
        end
      end

      def emit_binary(instr) # rubocop:disable Metrics/MethodLength
        load_operand(instr.left,  'x9')
        load_operand(instr.right, 'x10')

        case instr.op
        when :plus
          emit '  add x9, x9, x10'
        when :minus
          emit '  sub x9, x9, x10'
        when :star
          emit '  mul x9, x9, x10'
        when :slash
          emit '  sdiv x9, x9, x10'
        when :percent
          emit '  sdiv x11, x9, x10'
          emit '  msub x9, x11, x10, x9'
        when :amp
          emit '  and x9, x9, x10'
        when :pipe
          emit '  orr x9, x9, x10'
        when :caret
          emit '  eor x9, x9, x10'
        when :lshift
          emit '  lsl x9, x9, x10'
        when :rshift
          emit '  asr x9, x9, x10'
        when :eq
          emit '  cmp x9, x10'
          emit '  cset x9, eq'
        when :neq
          emit '  cmp x9, x10'
          emit '  cset x9, ne'
        when :lt
          emit '  cmp x9, x10'
          emit '  cset x9, lt'
        when :gt
          emit '  cmp x9, x10'
          emit '  cset x9, gt'
        when :leq
          emit '  cmp x9, x10'
          emit '  cset x9, le'
        when :geq
          emit '  cmp x9, x10'
          emit '  cset x9, ge'
        when :logical_and
          emit '  cmp x9, #0'
          emit '  cset x9, ne'
          emit '  cmp x10, #0'
          emit '  cset x10, ne'
          emit '  and x9, x9, x10'
        when :logical_or
          emit '  orr x9, x9, x10'
          emit '  cmp x9, #0'
          emit '  cset x9, ne'
        else
          emit '  add x9, x9, x10'
        end

        store_temp(instr.dst, 'x9')
      end

      def emit_fp_binary(instr) # rubocop:disable Metrics/MethodLength
        load_fp_operand(instr.left,  'd9')
        load_fp_operand(instr.right, 'd10')

        case instr.op
        when :plus  then emit '  fadd d9, d9, d10'
        when :minus then emit '  fsub d9, d9, d10'
        when :star  then emit '  fmul d9, d9, d10'
        when :slash then emit '  fdiv d9, d9, d10'
        when :eq
          emit '  fcmp d9, d10'; emit '  cset x9, eq'
          store_temp(instr.dst, 'x9'); return
        when :neq
          emit '  fcmp d9, d10'; emit '  cset x9, ne'
          store_temp(instr.dst, 'x9'); return
        when :lt
          emit '  fcmp d9, d10'; emit '  cset x9, mi'
          store_temp(instr.dst, 'x9'); return
        when :leq
          emit '  fcmp d9, d10'; emit '  cset x9, ls'
          store_temp(instr.dst, 'x9'); return
        when :gt
          emit '  fcmp d9, d10'; emit '  cset x9, gt'
          store_temp(instr.dst, 'x9'); return
        when :geq
          emit '  fcmp d9, d10'; emit '  cset x9, ge'
          store_temp(instr.dst, 'x9'); return
        else
          emit '  fadd d9, d9, d10'  # fallback
        end

        store_fp_temp(instr.dst, 'd9')
      end

      def emit_call(instr)
        args     = instr.args
        func_ref = instr.func

        # ── Compiler intrinsic: address of first variadic arg on stack ──────
        if func_ref.is_a?(IR::GlobalRef) && func_ref.name == '__occ_va_first_arg'
          emit "  add x9, x29, ##{@frame_sz}"
          store_temp(instr.dst, 'x9')
          return
        end

        # Variadic functions: named args in x0..x{N-1}, variadic args on stack
        named_count = func_ref.is_a?(IR::GlobalRef) ?
                        @mod.variadic_funcs[func_ref.name] : nil
        variadic = !named_count.nil?

        if variadic
          # Put named args in registers
          named_args = args.first(named_count)
          var_args   = args.drop(named_count)
          int_idx = 0
          named_args.each do |a|
            load_operand(a, ARG_REGS[int_idx])
            int_idx += 1
          end
          if var_args.any?
            stack_sz = align16(var_args.length * 8)
            emit "  sub sp, sp, ##{stack_sz}"
            var_args.each_with_index do |a, i|
              load_operand(a, 'x9')
              emit "  str x9, [sp, ##{i * 8}]"
            end
          end
          emit "  bl #{sym(func_ref.name)}"
          emit "  add sp, sp, ##{stack_sz}" if var_args.any?
        else
          # Non-variadic: integer args in x0-x7, FP args in d0-d7
          int_idx = 0
          fp_idx  = 0
          args.each do |a|
            if fp_operand?(a)
              load_fp_operand(a, "d#{fp_idx}") if fp_idx < 8
              fp_idx += 1
            else
              load_operand(a, ARG_REGS[int_idx]) if int_idx < ARG_REGS.length
              int_idx += 1
            end
          end
          case func_ref
          when IR::GlobalRef
            emit "  bl #{sym(func_ref.name)}"
          when IR::Temp
            load_operand(func_ref, 'x9')
            emit '  blr x9'
          end
        end

        # Capture return value
        func_name = func_ref.is_a?(IR::GlobalRef) ? func_ref.name : nil
        if @mod.fp_funcs.include?(func_name) || fp_ctype?(instr.type)
          store_fp_temp(instr.dst, 'd0')
        else
          store_temp(instr.dst, 'x0')
        end
      end

      # ── Stack / slot management ───────────────────────────────────────────────
      # Slots are positive offsets from x29 (frame pointer).
      # Layout: saved [x29,x30] at [sp,sp+8]; locals start at [fp+16].
      # Alloca temps for arrays/structs may occupy more than 8 bytes.

      def alloc_slot_for(temp)
        id = temp.id
        return @slot_map[id] if @slot_map.key?(id)
        sz = @alloca_sizes&.[](id) || 8
        # Keep 8-byte alignment
        @slot_next = ((@slot_next + 7) / 8 * 8)
        offset = @slot_next + 16   # +16 so first slot is at fp+16
        @slot_next += sz
        @slot_map[id] = offset
        offset
      end

      # Return the byte size a given ctype needs on the stack.
      # Used to properly allocate space for array and struct local variables.
      def ctype_stack_size(ctype)
        case ctype
        when OCC::Types::ArrayType
          return 8 if ctype.count.nil?  # unsized array — treat as pointer-sized
          sz = ctype.size rescue nil
          sz && sz > 0 ? sz : 8
        when OCC::Types::StructType
          sz = ctype.size rescue nil
          sz && sz > 0 ? sz : 8
        when OCC::Types::CType
          sz = ctype.size rescue nil
          sz && sz > 0 ? sz : 8
        else
          8
        end
      end

      def slot_of(temp) = alloc_slot_for(temp)

      def load_operand(op, reg)
        case op
        when IR::Const
          val = op.value.is_a?(Float) ? op.value.to_i : op.value
          if val >= 0 && val <= 65_535
            emit "  mov #{reg}, ##{val}"
          elsif val >= -65_536 && val < 0
            emit "  mov #{reg}, ##{val}"
          else
            # Encode as unsigned 64-bit with mov + movk for each 16-bit chunk
            uval = val & 0xFFFF_FFFF_FFFF_FFFF
            emit "  mov #{reg}, #0x#{(uval & 0xFFFF).to_s(16)}"
            [[16, (uval >> 16) & 0xFFFF],
             [32, (uval >> 32) & 0xFFFF],
             [48, (uval >> 48) & 0xFFFF]].each do |shift, chunk|
              emit "  movk #{reg}, #0x#{chunk.to_s(16)}, lsl ##{shift}" if chunk != 0
            end
          end
        when IR::Temp
          slot = slot_of(op)
          emit "  ldr #{reg}, [x29, ##{slot}]"
        when IR::GlobalRef
          emit "  adrp #{reg}, #{sym(op.name)}@PAGE"
          if @mod.func_names.include?(op.name)
            # Function reference: load the address (pointer to function)
            emit "  add  #{reg}, #{reg}, #{sym(op.name)}@PAGEOFF"
          else
            # Data reference: load the value stored at the address
            emit "  ldr  #{reg}, [#{reg}, #{sym(op.name)}@PAGEOFF]"
          end
        when IR::StringRef
          emit "  adrp #{reg}, l_str_#{op.id}@PAGE"
          emit "  add  #{reg}, #{reg}, l_str_#{op.id}@PAGEOFF"
        end
      end

      def store_temp(temp, reg)
        slot = alloc_slot_for(temp)
        emit "  str #{reg}, [x29, ##{slot}]"
      end

      def collect_temp_count(func)
        ids = Set.new
        func.blocks.each do |bb|
          bb.instrs.each do |i|
            %i[dst src left right ptr value cond].each do |field|
              next unless i.respond_to?(field)
              v = i.send(field)
              ids << v.id if v.is_a?(IR::Temp)
            end
          end
        end
        ids.length
      end

      def align16(n) = (n + 15) / 16 * 16
    end
  end
end
