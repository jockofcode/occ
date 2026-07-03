# frozen_string_literal: true

module OCC
  module Codegen
    # AMD64 (x86-64) System-V ABI code generator.
    # Targets both Linux (ELF) and macOS (Mach-O).
    # Uses AT&T syntax.
    #
    # Strategy: all temporaries live on the stack (stack-allocated virtual
    # registers). Register allocation is handled by spilling everything and
    # using %rax/%rcx/%rdx/%rsi/%rdi as scratch registers.
    #
    # FP convention (System V AMD64 ABI):
    #   FP args:   %xmm0–%xmm7 (independent from integer args)
    #   FP return: %xmm0
    #   Scratch:   %xmm8, %xmm9
    class AMD64 < Base
      # Integer argument registers (System-V ABI)
      ARG_REGS = %w[%rdi %rsi %rdx %rcx %r8 %r9].freeze

      def initialize(mod, target: :amd64_linux)
        super(mod)
        @target  = target
        @macos   = target == :amd64_macos
        @sym_pfx = @macos ? '_' : ''
      end

      private

      def sym(name) = "#{@sym_pfx}#{name}"

      # ── Sections / preamble ──────────────────────────────────────────────────

      def emit_preamble
        if @macos
          emit '.section __TEXT,__text,regular,pure_instructions'
        else
          emit '.section .text'
        end
      end

      def emit_string_constant(id, value)
        if @macos
          if value.include?("\0")
            emit '.section __TEXT,__const'
          else
            emit '.section __TEXT,__cstring,cstring_literals'
          end
        else
          emit '.section .rodata'
        end
        emit "L_str_#{id}:"
        emit "  .asciz #{asm_string(value)}"
        if @macos
          emit '.section __TEXT,__text,regular,pure_instructions'
        else
          emit '.section .text'
        end
        emit_blank
      end

      def emit_global(name, g)
        init = g[:init]
        if init
          if init.is_a?(Hash) && init[:kind] == :string
            if g[:type].is_a?(OCC::Types::ArrayType)
              # char arr[] = "str": emit string bytes inline at the global symbol.
              if @macos
                emit '.section __TEXT,__const'
                emit ".globl #{sym(name)}"
                emit "#{sym(name)}:"
                emit "  .asciz #{asm_string(init[:value])}"
                emit '.section __TEXT,__text,regular,pure_instructions'
              else
                emit '.section .rodata'
                emit ".globl #{name}"
                emit "#{name}:"
                emit "  .asciz #{asm_string(init[:value])}"
                emit '.section .text'
              end
            else
              str_lbl = "#{@macos ? 'l' : '.L'}gstr_#{name}"
              if @macos
                emit '.section __TEXT,__cstring,cstring_literals'
                emit "#{str_lbl}:"
                emit "  .asciz #{asm_string(init[:value])}"
                emit '.section __DATA,__data'
                emit ".globl #{sym(name)}"
                emit '.p2align 3'
                emit "#{sym(name)}:"
                emit "  .quad #{str_lbl}"
                emit '.section __TEXT,__text,regular,pure_instructions'
              else
                emit '.section .rodata'
                emit "#{str_lbl}:"
                emit "  .asciz #{asm_string(init[:value])}"
                emit '.section .data'
                emit ".globl #{name}"
                emit '.align 8'
                emit "#{name}:"
                emit "  .quad #{str_lbl}"
                emit '.section .text'
              end
            end
          elsif init.is_a?(Float)
            fp_dir = sz == 4 ? '.float' : '.double'
            al     = sz == 4 ? 4 : 8
            if @macos
              emit '.section __DATA,__data'
              emit ".globl #{sym(name)}"
              emit ".p2align #{Math.log2(al).to_i}"
              emit "#{sym(name)}:"
              emit "  #{fp_dir} #{init}"
              emit '.section __TEXT,__text,regular,pure_instructions'
            else
              emit '.section .data'
              emit ".globl #{name}"
              emit ".align #{al}"
              emit "#{name}:"
              emit "  #{fp_dir} #{init}"
              emit '.section .text'
            end
          elsif init.is_a?(Hash) && init[:kind] == :ref
            if @macos
              emit '.section __DATA,__data'
              emit ".globl #{sym(name)}"
              emit '.p2align 3'
              emit "#{sym(name)}:"
              ref_target = sym(init[:name])
              ref_target += " + #{init[:offset]}" if init[:offset] && init[:offset] != 0
              emit "  .quad #{ref_target}"
              emit '.section __TEXT,__text,regular,pure_instructions'
            else
              emit '.section .data'
              emit ".globl #{name}"
              emit '.align 8'
              emit "#{name}:"
              ref_target = init[:name].to_s
              ref_target += " + #{init[:offset]}" if init[:offset] && init[:offset] != 0
              emit "  .quad #{ref_target}"
              emit '.section .text'
            end
          elsif @macos
            # Integer scalar: emit as .quad so GlobalRef 8-byte loads work correctly.
            emit '.section __DATA,__data'
            emit ".globl #{sym(name)}"
            emit '.p2align 3'
            emit "#{sym(name)}:"
            emit "  .quad #{init}"
            emit '.section __TEXT,__text,regular,pure_instructions'
          else
            emit '.section .data'
            emit ".globl #{name}"
            emit '.align 8'
            emit "#{name}:"
            emit "  .quad #{init}"
            emit '.section .text'
          end
        elsif @macos
          size = type_byte_size(g[:type])
          emit ".comm #{sym(name)},#{size},3"
        else
          size = type_byte_size(g[:type])
          emit ".comm #{name},#{size},8"
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
        @func            = func
        @slot_map        = {}    # temp_id => stack offset from %rbp (negative)
        @slot_next       = -8    # next available slot (grows downward)
        @label_map       = {}    # IR label => asm label
        @alloca_slots    = Set.new   # temp IDs that are direct alloca stack slots
        @fp_alloca_slots = Set.new   # alloca slots holding fp values
        @alloca_ctypes   = {}        # temp_id => CType for alloca instructions
        @fp_temps        = Set.new   # temp IDs that hold fp values
        @float_pool      = []        # [{label:, value:}] per-function FP literals

        # Pre-scan: collect alloca temps and mark FP allocas
        func.blocks.each do |bb|
          bb.instrs.each do |i|
            next unless i.is_a?(IR::Alloca)
            @alloca_slots << i.dst.id
            @alloca_ctypes[i.dst.id] = i.ctype
            @fp_alloca_slots << i.dst.id if fp_ctype?(i.ctype)
          end
        end

        # Type-propagation pass to identify FP-valued temps
        compute_fp_temps(func)

        # Compute frame size: count all temporaries used
        all_temps = collect_temps(func)
        frame_sz  = align16(all_temps.length * 8 + 8)

        name = sym(func.name)
        emit ".globl #{name}" unless func.static
        emit "#{name}:"

        # Prologue
        emit '  pushq %rbp'
        emit '  movq %rsp, %rbp'
        emit "  subq $#{frame_sz}, %rsp"

        # Save incoming parameters — integer args in rdi/rsi/..., FP args in xmm0-xmm7.
        # Args beyond the 6th integer register are at [rbp+16], [rbp+24], etc. (SysV ABI).
        int_idx = 0
        xmm_idx = 0
        stack_param_idx = 0
        func.params.each_with_index do |p, idx|
          next unless p[:name]
          slot = alloc_slot_for(IR::Temp.new(idx))
          if fp_ctype?(p[:type])
            emit "  movsd %xmm#{xmm_idx}, #{slot}(%rbp)"
            xmm_idx += 1
          elsif int_idx < ARG_REGS.length
            emit "  movq #{ARG_REGS[int_idx]}, #{slot}(%rbp)"
            int_idx += 1
          else
            # Stack argument: caller pushed at [rbp+16+stack_param_idx*8]
            stack_off = 16 + stack_param_idx * 8
            emit "  movq #{stack_off}(%rbp), %rax"
            emit "  movq %rax, #{slot}(%rbp)"
            stack_param_idx += 1
            int_idx += 1
          end
        end

        # For variadic functions, save remaining integer registers so that
        # __occ_va_first_arg can point into a contiguous register-save area.
        if func.variadic
          @va_reg_save_base = nil   # offset of first variadic-register slot
          (int_idx...ARG_REGS.length).each do |i|
            slot = @slot_next
            @slot_next -= 8
            @va_reg_save_base = slot if i == int_idx
            emit "  movq #{ARG_REGS[i]}, #{slot}(%rbp)"
          end
        end

        # Emit basic blocks
        func.blocks.each { |bb| emit_block(bb) }

        # Float literal pool (per-function, after body)
        unless @float_pool.empty?
          if @macos
            emit '.section __TEXT,__literal8,8byte_literals'
          else
            emit '.section .rodata'
          end
          emit '.p2align 3'
          @float_pool.each do |entry|
            emit "#{entry[:label]}:"
            emit "  .double #{entry[:value]}"
          end
          if @macos
            emit '.section __TEXT,__text,regular,pure_instructions'
          else
            emit '.section .text'
          end
        end

        emit_blank
      end

      # ── Basic block ──────────────────────────────────────────────────────────

      def emit_block(bb)
        emit "#{func_local(bb.label)}:"
        bb.instrs.each { |i| emit_instr(i) }
      end

      def func_local(label) = ".L#{@func.name}_#{label}"

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

      # Load an FP operand into an XMM register.
      def load_fp_operand(op, xmm)
        case op
        when IR::Const
          val = op.value.to_f
          pool_id = @float_pool.length
          label   = ".Lflt_#{@func.name}_#{pool_id}"
          @float_pool << { label: label, value: val }
          emit "  movsd #{label}(%rip), #{xmm}"
        when IR::Temp
          slot = slot_of(op)
          emit "  movsd #{slot}(%rbp), #{xmm}"
        when IR::GlobalRef
          emit "  movsd #{sym(op.name)}(%rip), #{xmm}"
        end
      end

      # Store an XMM register to a temp's stack slot and mark it FP.
      def store_fp_temp(temp, xmm)
        slot = alloc_slot_for(temp)
        emit "  movsd #{xmm}, #{slot}(%rbp)"
        @fp_temps << temp.id
      end

      # ── Instruction emission ─────────────────────────────────────────────────

      def emit_instr(instr) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
        case instr
        when IR::Alloca
          alloc_slot_for(instr.dst)

        when IR::Copy
          if fp_operand?(instr.src)
            load_fp_operand(instr.src, '%xmm8')
            store_fp_temp(instr.dst, '%xmm8')
          else
            load_operand(instr.src, '%rax')
            store_temp(instr.dst, '%rax')
          end

        when IR::Load
          if instr.ptr.is_a?(IR::Temp) && @alloca_slots.include?(instr.ptr.id)
            if @fp_alloca_slots.include?(instr.ptr.id)
              alloca_ct = @alloca_ctypes[instr.ptr.id]
              slot = slot_of(instr.ptr)
              if alloca_ct.respond_to?(:size) && alloca_ct.size == 4
                # float (4-byte) slot: load as single, expand to double
                emit "  movss #{slot}(%rbp), %xmm8"
                emit '  cvtss2sd %xmm8, %xmm8'
              else
                emit "  movsd #{slot}(%rbp), %xmm8"
              end
              store_fp_temp(instr.dst, '%xmm8')
            else
              emit "  movq #{slot_of(instr.ptr)}(%rbp), %rax"
              store_temp(instr.dst, '%rax')
            end
          else
            load_operand(instr.ptr, '%rcx')
            case instr.elem_size
            when 1 then emit '  movzbl (%rcx), %eax'
            when 2 then emit '  movzwl (%rcx), %eax'
            when 4 then emit '  movl (%rcx), %eax'
            else        emit '  movq (%rcx), %rax'
            end
            store_temp(instr.dst, '%rax')
          end

        when IR::Store
          if instr.ptr.is_a?(IR::Temp) && @alloca_slots.include?(instr.ptr.id)
            if @fp_alloca_slots.include?(instr.ptr.id) || fp_operand?(instr.value)
              load_fp_operand(instr.value, '%xmm8')
              alloca_ct = @alloca_ctypes[instr.ptr.id]
              slot = slot_of(instr.ptr)
              if alloca_ct.respond_to?(:size) && alloca_ct.size == 4
                # float (4-byte) slot: narrow to single before storing so &f reads correct bytes
                emit '  cvtsd2ss %xmm8, %xmm8'
                emit "  movss %xmm8, #{slot}(%rbp)"
              else
                emit "  movsd %xmm8, #{slot}(%rbp)"
              end
              @fp_alloca_slots << instr.ptr.id
            elsif instr.elem_size > 8
              load_operand(instr.value, '%rsi')
              emit "  leaq #{slot_of(instr.ptr)}(%rbp), %rdi"
              emit_struct_copy('%rsi', '%rdi', instr.elem_size)
            elsif instr.type.is_a?(OCC::Types::StructType) && instr.elem_size.to_i.between?(1, 8)
              load_operand(instr.value, '%rsi')
              slot = slot_of(instr.ptr)
              if instr.elem_size <= 4
                emit '  movl (%rsi), %eax'
                emit "  movl %eax, #{slot}(%rbp)"
              else
                emit '  movq (%rsi), %rax'
                emit "  movq %rax, #{slot}(%rbp)"
              end
            else
              load_operand(instr.value, '%rax')
              emit "  movq %rax, #{slot_of(instr.ptr)}(%rbp)"
            end
          else
            load_operand(instr.value, '%rax')
            case instr.ptr
            when IR::Temp
              ptr_slot = slot_of(instr.ptr)
              emit "  movq #{ptr_slot}(%rbp), %rcx"
              if instr.elem_size > 8
                emit_struct_copy('%rax', '%rcx', instr.elem_size)
              elsif instr.type.is_a?(OCC::Types::StructType) && instr.elem_size.to_i.between?(1, 8)
                if instr.elem_size <= 4
                  emit '  movl (%rax), %edx'
                  emit '  movl %edx, (%rcx)'
                else
                  emit '  movq (%rax), %rdx'
                  emit '  movq %rdx, (%rcx)'
                end
              else
                case instr.elem_size
                when 1 then emit '  movb %al, (%rcx)'
                when 2 then emit '  movw %ax, (%rcx)'
                when 4 then emit '  movl %eax, (%rcx)'
                else        emit '  movq %rax, (%rcx)'
                end
              end
            when IR::GlobalRef
              if instr.elem_size > 8
                emit "  leaq #{sym(instr.ptr.name)}(%rip), %rcx"
                emit_struct_copy('%rax', '%rcx', instr.elem_size)
              elsif instr.type.is_a?(OCC::Types::StructType) && instr.elem_size.to_i.between?(1, 8)
                emit "  leaq #{sym(instr.ptr.name)}(%rip), %rcx"
                if instr.elem_size <= 4
                  emit '  movl (%rax), %edx'
                  emit '  movl %edx, (%rcx)'
                else
                  emit '  movq (%rax), %rdx'
                  emit '  movq %rdx, (%rcx)'
                end
              else
                case instr.elem_size
                when 1 then emit "  movb %al, #{sym(instr.ptr.name)}(%rip)"
                when 2 then emit "  movw %ax, #{sym(instr.ptr.name)}(%rip)"
                when 4 then emit "  movl %eax, #{sym(instr.ptr.name)}(%rip)"
                else        emit "  movq %rax, #{sym(instr.ptr.name)}(%rip)"
                end
              end
            end
          end

        when IR::AddrOf
          case instr.src
          when IR::Temp
            emit "  leaq #{slot_of(instr.src)}(%rbp), %rax"
          when IR::GlobalRef
            emit "  leaq #{sym(instr.src.name)}(%rip), %rax"
          end
          store_temp(instr.dst, '%rax')

        when IR::Gep
          load_operand(instr.ptr,   '%rcx')
          load_operand(instr.index, '%rdx')
          emit "  imulq $#{instr.elem_size}, %rdx" if instr.elem_size > 1
          emit '  addq %rdx, %rcx'
          store_temp(instr.dst, '%rcx')

        when IR::Unary
          load_operand(instr.src, '%rax')
          case instr.op
          when :neg    then emit '  negq %rax'
          when :not    then emit '  testq %rax, %rax'; emit '  sete %al'; emit '  movzbq %al, %rax'
          when :bitnot then emit '  notq %rax'
          end
          store_temp(instr.dst, '%rax')

        when IR::Binary
          if fp_operand?(instr.left) || fp_operand?(instr.right) || fp_ctype?(instr.type)
            emit_fp_binary(instr)
          else
            emit_binary(instr)
          end

        when IR::Call
          emit_call(instr)

        when IR::Jump
          emit "  jmp #{func_local(instr.target)}"

        when IR::CondJump
          load_operand(instr.cond, '%rax')
          emit '  testq %rax, %rax'
          emit "  jne #{func_local(instr.true_label)}"
          emit "  jmp #{func_local(instr.false_label)}"

        when IR::Return
          if instr.value
            if fp_operand?(instr.value)
              load_fp_operand(instr.value, '%xmm0')
            else
              load_operand(instr.value, '%rax')
            end
          end
          emit '  movq %rbp, %rsp'
          emit '  popq %rbp'
          emit '  retq'

        when IR::Cast
          if fp_operand?(instr.src) && fp_ctype?(instr.type)
            # FP → FP: float→double widening or no-op
            load_fp_operand(instr.src, '%xmm8')
            store_fp_temp(instr.dst, '%xmm8')
          elsif fp_operand?(instr.src) && !fp_ctype?(instr.type)
            # FP → integer truncation
            load_fp_operand(instr.src, '%xmm8')
            emit '  cvttsd2si %xmm8, %rax'
            store_temp(instr.dst, '%rax')
          elsif !fp_operand?(instr.src) && fp_ctype?(instr.type)
            # integer → FP conversion
            load_operand(instr.src, '%rax')
            emit '  cvtsi2sd %rax, %xmm8'
            store_fp_temp(instr.dst, '%xmm8')
          else
            # int → int: truncate/extend to target width
            load_operand(instr.src, '%rax')
            ct = instr.type
            if ct.is_a?(OCC::Types::IntegerType)
              case ct.size
              when 1
                emit(ct.signed? ? '  movsbq %al, %rax' : '  movzbq %al, %rax')
              when 2
                emit(ct.signed? ? '  movswq %ax, %rax' : '  movzwq %ax, %rax')
              when 4
                emit(ct.signed? ? '  movslq %eax, %rax' : '  movl %eax, %eax')
              end
            end
            store_temp(instr.dst, '%rax')
          end
        end
      end

      def emit_binary(instr) # rubocop:disable Metrics/MethodLength
        load_operand(instr.left,  '%rax')
        load_operand(instr.right, '%rcx')

        case instr.op
        when :plus
          emit '  addq %rcx, %rax'
        when :minus
          emit '  subq %rcx, %rax'
        when :star
          emit '  imulq %rcx, %rax'
        when :slash
          emit '  cqto'
          emit '  idivq %rcx'
        when :percent
          emit '  cqto'
          emit '  idivq %rcx'
          emit '  movq %rdx, %rax'
        when :amp
          emit '  andq %rcx, %rax'
        when :pipe
          emit '  orq %rcx, %rax'
        when :caret
          emit '  xorq %rcx, %rax'
        when :lshift
          emit '  movq %rcx, %rcx'
          emit '  shlq %cl, %rax'
        when :rshift
          emit '  shrq %cl, %rax'
        when :eq
          emit '  cmpq %rcx, %rax'
          emit '  sete %al'
          emit '  movzbq %al, %rax'
        when :neq
          emit '  cmpq %rcx, %rax'
          emit '  setne %al'
          emit '  movzbq %al, %rax'
        when :lt
          emit '  cmpq %rcx, %rax'
          emit '  setl %al'
          emit '  movzbq %al, %rax'
        when :gt
          emit '  cmpq %rcx, %rax'
          emit '  setg %al'
          emit '  movzbq %al, %rax'
        when :leq
          emit '  cmpq %rcx, %rax'
          emit '  setle %al'
          emit '  movzbq %al, %rax'
        when :geq
          emit '  cmpq %rcx, %rax'
          emit '  setge %al'
          emit '  movzbq %al, %rax'
        when :logical_and
          emit '  testq %rax, %rax'
          emit '  setne %al'
          emit '  testq %rcx, %rcx'
          emit '  setne %cl'
          emit '  andb %cl, %al'
          emit '  movzbq %al, %rax'
        when :logical_or
          emit '  orq %rcx, %rax'
          emit '  setne %al'
          emit '  movzbq %al, %rax'
        else
          emit '  addq %rcx, %rax'   # fallback
        end

        store_temp(instr.dst, '%rax')
      end

      def emit_fp_binary(instr) # rubocop:disable Metrics/MethodLength
        load_fp_operand(instr.left,  '%xmm8')
        load_fp_operand(instr.right, '%xmm9')

        case instr.op
        when :plus  then emit '  addsd %xmm9, %xmm8'
        when :minus then emit '  subsd %xmm9, %xmm8'
        when :star  then emit '  mulsd %xmm9, %xmm8'
        when :slash then emit '  divsd %xmm9, %xmm8'
        when :eq
          emit '  ucomisd %xmm9, %xmm8'; emit '  sete %al'; emit '  movzbq %al, %rax'
          store_temp(instr.dst, '%rax'); return
        when :neq
          emit '  ucomisd %xmm9, %xmm8'; emit '  setne %al'; emit '  movzbq %al, %rax'
          store_temp(instr.dst, '%rax'); return
        when :lt
          emit '  ucomisd %xmm8, %xmm9'; emit '  seta %al'; emit '  movzbq %al, %rax'
          store_temp(instr.dst, '%rax'); return
        when :leq
          emit '  ucomisd %xmm8, %xmm9'; emit '  setae %al'; emit '  movzbq %al, %rax'
          store_temp(instr.dst, '%rax'); return
        when :gt
          emit '  ucomisd %xmm9, %xmm8'; emit '  seta %al'; emit '  movzbq %al, %rax'
          store_temp(instr.dst, '%rax'); return
        when :geq
          emit '  ucomisd %xmm9, %xmm8'; emit '  setae %al'; emit '  movzbq %al, %rax'
          store_temp(instr.dst, '%rax'); return
        else
          emit '  addsd %xmm9, %xmm8'   # fallback
        end

        store_fp_temp(instr.dst, '%xmm8')
      end

      def emit_call(instr)
        args     = instr.args
        func_ref = instr.func

        # ── Compiler intrinsic: address of first variadic arg ────────────────
        if func_ref.is_a?(IR::GlobalRef) && func_ref.name == '__occ_va_first_arg'
          if @va_reg_save_base
            # Variadic args are in the register-save area immediately after named params
            emit "  leaq #{@va_reg_save_base}(%rbp), %rax"
          else
            # Fallback: stack args start at rbp+16 (past saved rbp + return addr)
            emit '  leaq 16(%rbp), %rax'
          end
          store_temp(instr.dst, '%rax')
          return
        end

        # System V AMD64: integer args in rdi/rsi/rdx/rcx/r8/r9,
        #                 FP args in xmm0-xmm7 (independent slots)
        int_idx = 0
        fp_idx  = 0
        stack_args = []

        args.each do |a|
          if fp_operand?(a)
            if fp_idx < 8
              load_fp_operand(a, "%xmm#{fp_idx}")
              fp_idx += 1
            else
              stack_args << a
            end
          else
            if int_idx < ARG_REGS.length
              load_operand(a, ARG_REGS[int_idx])
              int_idx += 1
            else
              stack_args << a
            end
          end
        end

        # Push extra args right to left
        stack_args.reverse.each do |a|
          load_operand(a, '%rax')
          emit '  pushq %rax'
        end

        # For variadic functions, %al must hold number of FP registers used
        variadic = func_ref.is_a?(IR::GlobalRef) &&
                   @mod.variadic_funcs.key?(func_ref.name)
        if variadic
          emit "  movl $#{fp_idx}, %eax"
        end

        # Align stack to 16 before call
        emit '  andq $-16, %rsp'

        target = case func_ref
                 when IR::GlobalRef
                   if @mod.func_names.include?(func_ref.name) || !@mod.globals.key?(func_ref.name)
                     sym(func_ref.name).to_s
                   else
                     load_operand(func_ref, '%r11')
                     '*%r11'
                   end
                 when IR::Temp
                   load_operand(func_ref, '%r11')
                   '*%r11'
                 else func_ref.to_s
                 end

        emit "  callq #{target}"

        # Capture return value
        func_name = func_ref.is_a?(IR::GlobalRef) ? func_ref.name : nil
        if @mod.fp_funcs.include?(func_name) || fp_ctype?(instr.type)
          store_fp_temp(instr.dst, '%xmm0')
        else
          store_temp(instr.dst, '%rax')
        end
      end

      # ── Stack / slot management ───────────────────────────────────────────────

      def alloc_slot_for(temp)
        id = temp.id
        return @slot_map[id] if @slot_map.key?(id)
        offset = @slot_next
        @slot_map[id] = offset
        @slot_next -= 8
        offset
      end

      def slot_of(temp)
        alloc_slot_for(temp)
      end

      def load_operand(op, reg)
        case op
        when IR::Const
          val = op.value.is_a?(Float) ? op.value.to_i : op.value
          emit "  movq $#{val}, #{reg}"
        when IR::Temp
          slot = slot_of(op)
          emit "  movq #{slot}(%rbp), #{reg}"
        when IR::GlobalRef
          emit "  movq #{sym(op.name)}(%rip), #{reg}"
        when IR::StringRef
          emit "  leaq L_str_#{op.id}(%rip), #{reg}"
        end
      end

      def store_temp(temp, reg)
        slot = alloc_slot_for(temp)
        emit "  movq #{reg}, #{slot}(%rbp)"
      end

      def emit_struct_copy(src, dst, size)
        offset = 0
        while offset + 8 <= size
          emit "  movq #{offset}(#{src}), %r10"
          emit "  movq %r10, #{offset}(#{dst})"
          offset += 8
        end
        if offset + 4 <= size
          emit "  movl #{offset}(#{src}), %r10d"
          emit "  movl %r10d, #{offset}(#{dst})"
          offset += 4
        end
        if offset + 2 <= size
          emit "  movw #{offset}(#{src}), %r10w"
          emit "  movw %r10w, #{offset}(#{dst})"
          offset += 2
        end
        if offset < size
          emit "  movb #{offset}(#{src}), %r10b"
          emit "  movb %r10b, #{offset}(#{dst})"
        end
      end

      # ── Helpers ───────────────────────────────────────────────────────────────

      def collect_temps(func)
        temps = Set.new
        func.blocks.each do |bb|
          bb.instrs.each do |i|
            %i[dst src left right ptr value cond].each do |field|
              next unless i.respond_to?(field)
              v = i.send(field)
              temps << v.id if v.is_a?(IR::Temp)
            end
          end
        end
        temps
      end

      def align16(n) = (n + 15) / 16 * 16
    end
  end
end
