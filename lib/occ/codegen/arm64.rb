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
        if value.include?("\0")
          emit '.section __TEXT,__const'
        else
          emit '.section __TEXT,__cstring,cstring_literals'
        end
        emit "l_str_#{id}:"
        emit "  .asciz #{asm_string(value)}"
        emit '.section __TEXT,__text,regular,pure_instructions'
        emit_blank
      end

      # Emit an ARM64 macOS Thread Local Variable descriptor.
      # Each TLS variable needs a TLV descriptor in __DATA,__thread_vars and
      # zero-initialised storage in __DATA,__thread_bss.
      def emit_tls_global(name, g)
        size  = type_byte_size(g[:type])
        align = (size >= 8 ? 3 : size >= 4 ? 2 : size >= 2 ? 1 : 0)
        init_lbl = "#{sym(name)}$tlv$init"

        # Zero-initialised TLS backing store (macOS .tbss directive)
        emit ".tbss #{init_lbl}, #{size}, #{align}"

        # TLV descriptor in __thread_vars
        emit '.section __DATA,__thread_vars,thread_local_variables'
        emit ".globl #{sym(name)}"
        emit '.p2align 3'
        emit "#{sym(name)}:"
        emit '  .quad __tlv_bootstrap'
        emit '  .quad 0'
        emit "  .quad #{init_lbl}"

        emit '.section __TEXT,__text,regular,pure_instructions'
      end

      # Load the address of a TLS variable into x0 via the TLV descriptor.
      # After return: x0 = &varname  (caller-saved; callee must preserve any live regs)
      def emit_tls_addr(name)
        emit "  adrp x0, #{sym(name)}@TLVPPAGE"
        emit "  ldr  x0, [x0, #{sym(name)}@TLVPPAGEOFF]"
        emit '  ldr  x8, [x0]'
        emit '  blr  x8'
      end

      # Load the value of a TLS variable into reg.
      def emit_tls_load(name, reg)
        g_type = @mod.tls_globals[name][:type]
        g_sz   = begin
                   (g_type.respond_to?(:unqualified) ? g_type.unqualified : g_type)
                     .then { |t| t.respond_to?(:byte_size) ? t.byte_size : type_byte_size(t) }
                 rescue StandardError
                   8
                 end
        emit_tls_addr(name)
        # x0 now holds the address of the TLS variable; load from it
        # ARM64: writing to w-register zero-extends to the full x-register automatically
        w_reg = reg.start_with?('x') ? "w#{reg[1..]}" : reg
        case g_sz
        when 1 then emit "  ldrb #{w_reg}, [x0]"
        when 2 then emit "  ldrh #{w_reg}, [x0]"
        when 4 then emit "  ldr  #{w_reg}, [x0]"
        else        emit "  ldr  #{reg}, [x0]"
        end
      end

      def emit_global(name, g)
        is_static = g[:static]
        init = g[:init]
        if init
          if init.is_a?(Hash) && init[:kind] == :initializer_list
            emit_compound_global(name, g, init)
          elsif init.is_a?(Hash) && init[:kind] == :string
            if g[:type].is_a?(OCC::Types::ArrayType)
              # char arr[] = "str": emit string bytes inline at the global symbol.
              # Using __TEXT,__const avoids cstring merging which breaks embedded nulls.
              emit '.section __TEXT,__const'
              emit ".globl #{sym(name)}" unless is_static
              emit "#{sym(name)}:"
              emit "  .asciz #{asm_string(init[:value])}"
            else
              # char *ptr = "str": emit cstring then a pointer to it in __data
              str_lbl = "l_gstr_#{name}"
              emit '.section __TEXT,__cstring,cstring_literals'
              emit "#{str_lbl}:"
              emit "  .asciz #{asm_string(init[:value])}"
              emit '.section __DATA,__data'
              emit ".globl #{sym(name)}" unless is_static
              emit '.p2align 3'
              emit "#{sym(name)}:"
              emit "  .quad #{str_lbl}"
            end
          elsif init.is_a?(Float)
            sz = type_byte_size(g[:type])
            emit '.section __DATA,__data'
            emit ".globl #{sym(name)}" unless is_static
            emit ".p2align #{sz == 4 ? 2 : 3}"
            emit "#{sym(name)}:"
            emit(sz == 4 ? "  .float #{init}" : "  .double #{init}")
          elsif init.is_a?(Hash) && init[:kind] == :ref
            emit '.section __DATA,__data'
            emit ".globl #{sym(name)}" unless is_static
            emit '.p2align 3'
            emit "#{sym(name)}:"
            ref_target = sym(init[:name])
            ref_target += " + #{init[:offset]}" if init[:offset] && init[:offset] != 0
            emit "  .quad #{ref_target}"
          else
            # Integer scalar: always emit as .quad so GlobalRef 8-byte loads work correctly.
            emit '.section __DATA,__data'
            emit ".globl #{sym(name)}" unless is_static
            emit '.p2align 3'
            emit "#{sym(name)}:"
            emit "  .quad #{init}"
          end
          emit '.section __TEXT,__text,regular,pure_instructions'
        else
          size = type_byte_size(g[:type])
          if is_static
            # Static zero-initialized: use .zerofill in __BSS without .globl so the
            # symbol stays local to this translation unit.
            emit ".zerofill __DATA,__bss,#{sym(name)},#{size},3"
          else
            emit ".comm #{sym(name)},#{size},3"
          end
        end
      end

      # Emit a compound (struct/array) global initializer into __DATA/__data.
      # Strings embedded in the initializer are placed in __TEXT/__cstring first.
      def emit_compound_global(name, g, init)
        type = g[:type]
        @cstring_counter ||= 0

        # First pass: collect all string literals and assign labels
        strings = collect_compound_strings(init, name)

        # Emit all strings into __cstring
        unless strings.empty?
          emit '.section __TEXT,__cstring,cstring_literals'
          strings.each do |lbl, val|
            emit "#{lbl}:"
            emit "  .asciz #{asm_string(val)}"
          end
        end

        # Emit the data
        emit '.section __DATA,__data'
        emit ".globl #{sym(name)}" unless g[:static]
        emit '.p2align 3'
        emit "#{sym(name)}:"

        emit_compound_init_data(type, init[:items], strings)
      end

      # Extract the raw value from an initializer item, which may be in wrapped
      # form {designators:, value:} (from eval_const_init) or already a plain value.
      def item_raw_value(item)
        item.is_a?(Hash) && item.key?(:designators) ? item[:value] : item
      end

      # Return the field designator name from an item, or nil if positional.
      def item_field_name(item)
        return nil unless item.is_a?(Hash) && item[:designators]&.any?
        item[:designators].find { |d| d[0] == :field }&.last
      end

      def item_index_designator(item)
        return nil unless item.is_a?(Hash) && item[:designators]&.any?
        item[:designators].find { |d| d[0] == :index }
      end

      # Recursively assign labels to string items in a compound initializer (mutates items).
      def collect_compound_strings(init_node, prefix)
        result = {}
        return result unless init_node.is_a?(Hash) && init_node[:kind] == :initializer_list
        (init_node[:items] || []).each_with_index do |item, i|
          raw = item_raw_value(item)
          next unless raw.is_a?(Hash)
          if raw[:kind] == :string
            lbl = "l_cstr_#{prefix}_#{@cstring_counter += 1}"
            result[lbl] = raw[:value]
            raw[:_label] = lbl
          elsif raw[:kind] == :initializer_list
            result.merge!(collect_compound_strings(raw, "#{prefix}_#{i}"))
          end
        end
        result
      end

      # Emit raw bytes for a compound initializer matched against `type`.
      def emit_compound_init_data(type, items, strings)
        bare = type.respond_to?(:unqualified) ? type.unqualified : type
        if bare.is_a?(OCC::Types::ArrayType)
          elem_type = bare.element
          elem_values = {}
          cursor = 0
          (items || []).each do |item|
            raw = item_raw_value(item)
            designators = item.is_a?(Hash) ? (item[:designators] || []) : []
            index_pos = designators.index { |d| d[0] == :index }
            idx = if index_pos
                    designators[index_pos][1]
                  else
                    cursor
                  end
            next unless idx.is_a?(Integer)

            remaining = index_pos ? designators[(index_pos + 1)..] : []
            raw = { kind: :initializer_list, items: [{ designators: remaining, value: raw }] } if remaining && !remaining.empty?
            elem_values[idx] = raw
            cursor = idx + 1
          end

          limit = bare.count || ((elem_values.keys.max || -1) + 1)
          limit.times do |idx|
            raw = elem_values[idx]
            if raw.is_a?(Hash) && raw[:kind] == :initializer_list
              emit_compound_init_data(elem_type, raw[:items], strings)
            elsif raw.nil?
              emit "  .zero #{type_byte_size(elem_type)}"
            else
              emit_compound_field_value(raw, elem_type, strings)
            end
          end
        elsif bare.is_a?(OCC::Types::StructType)
          emit_struct_init_data(bare, items, strings)
        else
          # Scalar fallback — emit each item as one element of `type` size
          items.each { |item| emit_compound_field_value(item_raw_value(item), type, strings) }
        end
      end

      def emit_packed_bytes(value, sz)
        case sz
        when 1 then emit "  .byte #{value & 0xFF}"
        when 2 then emit "  .short #{value & 0xFFFF}"
        when 4 then emit "  .long #{value & 0xFFFFFFFF}"
        when 8 then emit "  .quad #{value & 0xFFFF_FFFF_FFFF_FFFF}"
        else
          remaining = value
          sz.times do
            emit "  .byte #{remaining & 0xFF}"
            remaining >>= 8
          end
        end
      end

      def emit_struct_init_data(struct_type, items, strings)
        fields   = struct_type.fields
        n_fields = fields.length

        # Build field_name → index map for designator resolution.
        field_by_name = {}
        fields.each_with_index { |f, i| field_by_name[f[:name].to_s] = i }

        # Assign raw values to field indices using designators; fall back to positional.
        field_values = {}
        cursor = 0
        (items || []).each do |item|
          raw = item_raw_value(item)
          designators = item.is_a?(Hash) ? (item[:designators] || []) : []
          field_pos = designators.index { |d| d[0] == :field }
          if field_pos
            idx = field_by_name[designators[field_pos].last.to_s]
            if idx
              remaining = designators[(field_pos + 1)..]
              raw = { kind: :initializer_list, items: [{ designators: remaining, value: raw }] } if remaining && !remaining.empty?
              field_values[idx] = raw
              cursor = idx + 1
            end
          else
            field_values[cursor] = raw
            cursor += 1
          end
        end

        cur_off = 0
        fi      = 0

        while fi < n_fields
          field     = fields[fi]
          field_off = field[:offset]
          ft        = field[:type]

          if field[:bit_width]
            # Bitfield: collect all fields sharing this storage unit/group and pack them.
            unit_off  = field_off
            packed    = 0
            nfi       = fi
            while nfi < n_fields
              bf = fields[nfi]
              break unless bf[:bit_width] && bf[:offset] == unit_off
              val     = field_values[nfi]
              val     = val.is_a?(Integer) ? val : 0
              mask    = (1 << bf[:bit_width]) - 1
              packed |= (val & mask) << bf[:bit_offset]
              nfi    += 1
            end
            unit_size = fields[nfi - 1][:unit_size]
            fi = nfi

            next if unit_off < cur_off

            if unit_off > cur_off
              emit "  .zero #{unit_off - cur_off}"
              cur_off = unit_off
            end

            emit_packed_bytes(packed, unit_size)
            cur_off = unit_off + unit_size
          else
            # Regular (non-bitfield) field. Skip if offset already covered
            # (handles union members that all share the same byte offset).
            if field_off < cur_off
              fi += 1
              next
            end

            fsz = type_byte_size(ft)

            if field_off > cur_off
              emit "  .zero #{field_off - cur_off}"
              cur_off = field_off
            end

            item = field_values[fi]
            if item.nil?
              emit "  .zero #{fsz}"
            elsif item.is_a?(Hash) && item[:kind] == :initializer_list
              emit_compound_init_data(ft, item[:items], strings)
            else
              emit_compound_field_value(item, ft, strings)
            end
            cur_off = field_off + fsz
            fi += 1
          end
        end

        if struct_type.size > cur_off
          emit "  .zero #{struct_type.size - cur_off}"
        end
      end

      def emit_compound_field_value(val, field_type, _strings)
        fsz = type_byte_size(field_type)
        case val
        when nil
          emit "  .zero #{fsz}"
        when Integer
          case fsz
          when 1 then emit "  .byte #{val & 0xFF}"
          when 2 then emit "  .short #{val & 0xFFFF}"
          when 4 then emit "  .long #{val & 0xFFFFFFFF}"
          else        emit "  .quad #{val}"
          end
        when Float
          if fsz == 4
            emit "  .float #{val}"
          else
            emit "  .double #{val}"
          end
        when Hash
          case val[:kind]
          when :string
            if field_type.is_a?(OCC::Types::ArrayType)
              # char arr[N] = "str" inside a struct: inline the bytes
              bytes = val[:value].bytes[0...fsz]
              bytes << 0 while bytes.length < fsz
              bytes.each { |b| emit "  .byte #{b}" }
            else
              lbl = val[:_label]
              emit "  .quad #{lbl}"
            end
          when :ref
            ref_target = sym(val[:name])
            ref_target += " + #{val[:offset]}" if val[:offset] && val[:offset] != 0
            emit "  .quad #{ref_target}"
          else
            emit "  .zero #{fsz}"
          end
        else
          emit "  .zero #{fsz}"
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
        @alloca_ctypes = {}       # temp_id => ctype (for correct-width loads)
        @fp_alloca_slots = Set.new # alloca slots holding fp values
        @fp_temps      = Set.new  # temp IDs that hold fp (double/float) values
        @float_pool    = []   # [{label:, value:}] for literal-pool fp constants
        @cond_skip_seq = 0    # unique suffix for CondJump skip labels

        # Pre-scan: collect alloca temps, their sizes, and mark FP allocas
        alloca_extra = 0  # extra bytes beyond 8 for oversized alloca temps
        func.blocks.each do |bb|
          bb.instrs.each do |i|
            next unless i.is_a?(IR::Alloca)
            @alloca_slots << i.dst.id
            sz = ctype_stack_size(i.ctype)
            sz_aligned = (sz + 7) / 8 * 8  # round to 8-byte multiple for slot advancement
            @alloca_sizes[i.dst.id] = sz    # keep true size for load-width detection
            @alloca_ctypes[i.dst.id] = i.ctype
            alloca_extra += [sz_aligned - 8, 0].max
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
        emit ".globl #{name}" unless func.static
        emit '.p2align 2'
        emit "#{name}:"

        # Prologue: save fp and lr, set up frame pointer.
        # stp pre-index immediate is limited to [-512, 504]; use sub+stp for large frames.
        if frame_sz <= 504
          emit "  stp x29, x30, [sp, #-#{frame_sz}]!"
          emit '  mov x29, sp'
        else
          emit_sp_sub(frame_sz)
          emit '  stp x29, x30, [sp]'
          emit '  mov x29, sp'
        end

        # Save incoming parameters — integer args in x0-x7, FP args in d0-d7.
        # Args beyond the 8th integer register are passed on the stack by the caller
        # at [x29, #frame_sz], [x29, #frame_sz+8], etc.
        # Placeholder entries (name=nil) still consume a register slot so that
        # multi-register struct params land at the right positions.
        int_idx = 0
        fp_idx  = 0
        stack_param_idx = 0
        func.params.each_with_index do |p, idx|
          slot = alloc_slot_for(IR::Temp.new(idx))
          if fp_ctype?(p[:type])
            emit_fp_slot_store("d#{fp_idx}", slot)
            fp_idx += 1
          elsif int_idx < ARG_REGS.length
            emit_slot_store(ARG_REGS[int_idx], slot)
            int_idx += 1
          else
            # Stack argument: caller placed it at [x29, #frame_sz + stack_param_idx*8]
            stack_off = frame_sz + stack_param_idx * 8
            if stack_off <= 32_760
              emit "  ldr x9, [x29, ##{stack_off}]"
            else
              emit "  mov x16, ##{stack_off}"
              emit '  add x16, x29, x16'
              emit '  ldr x9, [x16]'
            end
            emit_slot_store('x9', slot)
            stack_param_idx += 1
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

        # __attribute__((constructor)): register function in __mod_init_func so
        # the dynamic linker calls it before main().
        if func.constructor
          emit '.section __DATA,__mod_init_func,mod_init_funcs'
          emit '.p2align 3'
          emit "  .quad #{name}"
          emit '.section __TEXT,__text'
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
        # Seed FP params — their temps are Temp(0), Temp(1), ... in param order.
        func.params.each_with_index do |p, idx|
          @fp_temps << idx if p[:type] && fp_ctype?(p[:type])
        end

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
                     # Comparison results are always int (0/1), never FP
                     fp_cmp_ops = %i[eq neq lt gt leq geq ult ugt uleq ugeq]
                     !fp_cmp_ops.include?(i.op) &&
                       (fp_operand?(i.left) || fp_operand?(i.right) || fp_ctype?(i.type))
                   when IR::Call
                     name = i.func.is_a?(IR::GlobalRef) ? i.func.name : nil
                     (name && @mod.fp_funcs.include?(name)) || fp_ctype?(i.type)
                   when IR::Unary
                     fp_operand?(i.src)
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
          if @fp_temps.include?(op.id)
            emit_fp_slot_load(dreg, slot)
          else
            # Integer temp used in FP context — convert
            emit_slot_load('x9', slot)
            emit "  scvtf #{dreg}, x9"
          end
        when IR::GlobalRef
          emit "  adrp x9, #{sym(op.name)}@PAGE"
          emit "  ldr  #{dreg}, [x9, #{sym(op.name)}@PAGEOFF]"
        end
      end

      # Store an FP register (dreg) to a temp's stack slot and mark it FP.
      def store_fp_temp(temp, dreg)
        slot = alloc_slot_for(temp)
        emit_fp_slot_store(dreg, slot)
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
              alloca_ct = @alloca_ctypes[instr.ptr.id]
              slot = slot_of(instr.ptr)
              if alloca_ct.respond_to?(:size) && alloca_ct.size == 4
                # float (4-byte) slot: load as single, expand to double for computation
                emit_fp_slot_load('s10', slot)
                emit '  fcvt d10, s10'
              else
                emit_fp_slot_load('d10', slot)
              end
              store_fp_temp(instr.dst, 'd10')
            else
              # Use a width-appropriate load to avoid reading garbage in upper bytes
              # when a smaller type (int=4, short=2, char=1) was stored via a pointer.
              alloca_ct = @alloca_ctypes[instr.ptr.id]
              alloca_sz = @alloca_sizes[instr.ptr.id] || 8
              if alloca_sz < 8 && alloca_ct.is_a?(OCC::Types::IntegerType)
                signed = alloca_ct.signed?
                emit_alloca_load(slot_of(instr.ptr), alloca_sz, signed)
              else
                emit_slot_load('x10', slot_of(instr.ptr))
              end
              store_temp(instr.dst, 'x10')
            end
          else
            load_operand(instr.ptr, 'x9')
            if fp_ctype?(instr.type)
              case instr.elem_size
              when 4 then emit '  ldr s10, [x9]'; emit '  fcvt d10, s10'
              else        emit '  ldr d10, [x9]'
              end
              store_fp_temp(instr.dst, 'd10')
            else
              signed = instr.type.is_a?(OCC::Types::IntegerType) && instr.type.signed?
              case instr.elem_size
              when 1 then emit(signed ? '  ldrsb x10, [x9]' : '  ldrb w10, [x9]')
              when 2 then emit(signed ? '  ldrsh x10, [x9]' : '  ldrh w10, [x9]')
              when 4 then emit(signed ? '  ldrsw x10, [x9]' : '  ldr w10, [x9]')
              else        emit '  ldr x10, [x9]'
              end
              store_temp(instr.dst, 'x10')
            end
          end

        when IR::Store
          if instr.ptr.is_a?(IR::Temp) && @alloca_slots.include?(instr.ptr.id)
            if @fp_alloca_slots.include?(instr.ptr.id) || fp_operand?(instr.value)
              load_fp_operand(instr.value, 'd9')
              alloca_ct = @alloca_ctypes[instr.ptr.id]
              slot = slot_of(instr.ptr)
              if alloca_ct.respond_to?(:size) && alloca_ct.size == 4
                # float (4-byte) slot: narrow to single before storing so &f reads correct bytes
                emit '  fcvt s9, d9'
                emit_fp_slot_store('s9', slot)
              else
                emit_fp_slot_store('d9', slot)
              end
              @fp_alloca_slots << instr.ptr.id  # mark slot as FP once we store FP into it
            elsif instr.elem_size.to_i > 8
              # Large struct copy into local slot: x9 = source addr, x10 = dest addr.
              # If source is a constant (e.g. zero-init), fill directly — do not use it as an address.
              load_operand(instr.value, 'x9')
              emit_addr_from_fp('x10', slot_of(instr.ptr))
              if instr.value.is_a?(IR::Const)
                emit_struct_fill('x9', 'x10', instr.elem_size)
              else
                emit_struct_copy('x9', 'x10', instr.elem_size)
              end
            elsif instr.type.is_a?(OCC::Types::StructType) && instr.elem_size.to_i.between?(1, 8)
              # Small struct: source is a struct address temp OR a constant (e.g. zero-init).
              # Use emit_struct_copy/fill so load/store widths match the actual struct size.
              load_operand(instr.value, 'x9')
              emit_addr_from_fp('x10', slot_of(instr.ptr))
              if instr.value.is_a?(IR::Const)
                emit_struct_fill('x9', 'x10', instr.elem_size)
              else
                emit_struct_copy('x9', 'x10', instr.elem_size)
              end
            else
              load_operand(instr.value, 'x9')
              emit_slot_store('x9', slot_of(instr.ptr))
            end
          else
            fp_field = fp_ctype?(instr.type) if instr.type
            fp_val = fp_field || fp_operand?(instr.value)
            if fp_val
              load_fp_operand(instr.value, 'd9')
            else
              load_operand(instr.value, 'x9')
            end
            case instr.ptr
            when IR::Temp
              ptr_slot = slot_of(instr.ptr)
              emit_slot_load('x10', ptr_slot)
              if fp_val
                emit '  str d9, [x10]'
              elsif instr.elem_size > 8
                if instr.value.is_a?(IR::Const)
                  emit_struct_fill('x9', 'x10', instr.elem_size)
                else
                  emit_struct_copy('x9', 'x10', instr.elem_size)
                end
              elsif instr.type.is_a?(OCC::Types::StructType) && instr.elem_size.to_i.between?(1, 8)
                if instr.value.is_a?(IR::Const)
                  emit_struct_fill('x9', 'x10', instr.elem_size)
                else
                  emit_struct_copy('x9', 'x10', instr.elem_size)
                end
              else
                case instr.elem_size
                when 1 then emit '  strb w9, [x10]'
                when 2 then emit '  strh w9, [x10]'
                when 4 then emit '  str w9, [x10]'
                else        emit '  str x9, [x10]'
                end
              end
            when IR::GlobalRef
              if @mod.tls_globals.key?(instr.ptr.name)
                emit_tls_addr(instr.ptr.name)
                emit '  mov x10, x0'
              else
                emit "  adrp x10, #{sym(instr.ptr.name)}@PAGE"
                emit "  add  x10, x10, #{sym(instr.ptr.name)}@PAGEOFF"
              end
              if fp_val
                emit '  str d9, [x10]'
              elsif instr.elem_size > 8
                if instr.value.is_a?(IR::Const)
                  emit_struct_fill('x9', 'x10', instr.elem_size)
                else
                  emit_struct_copy('x9', 'x10', instr.elem_size)
                end
              elsif instr.type.is_a?(OCC::Types::StructType) && instr.elem_size.to_i.between?(1, 8)
                if instr.value.is_a?(IR::Const)
                  emit_struct_fill('x9', 'x10', instr.elem_size)
                else
                  emit_struct_copy('x9', 'x10', instr.elem_size)
                end
              else
                case instr.elem_size
                when 1 then emit '  strb w9, [x10]'
                when 2 then emit '  strh w9, [x10]'
                when 4 then emit '  str w9, [x10]'
                else        emit '  str x9, [x10]'
                end
              end
            end
          end

        when IR::AddrOf
          case instr.src
          when IR::Temp
            emit_addr_from_fp('x9', slot_of(instr.src))
          when IR::GlobalRef
            if @mod.tls_globals.key?(instr.src.name)
              emit_tls_addr(instr.src.name)
              emit '  mov x9, x0'
            elsif @mod.defined_funcs.include?(instr.src.name) ||
                  @mod.globals.key?(instr.src.name)
              # Locally defined symbol: direct page-relative address
              emit "  adrp x9, #{sym(instr.src.name)}@PAGE"
              emit "  add  x9, x9, #{sym(instr.src.name)}@PAGEOFF"
            else
              # External symbol (function or data): GOT-indirect address
              emit "  adrp x9, #{sym(instr.src.name)}@GOTPAGE"
              emit "  ldr  x9, [x9, #{sym(instr.src.name)}@GOTPAGEOFF]"
            end
          end
          store_temp(instr.dst, 'x9')

        when IR::StackPointer
          emit '  mov x9, sp'
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
          if instr.op == :neg && fp_operand?(instr.src)
            load_fp_operand(instr.src, 'd9')
            emit '  fneg d9, d9'
            store_fp_temp(instr.dst, 'd9')
          else
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
          end

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
          # Use cbz to a local skip label + unconditional b for the true branch.
          # cbnz/cbz are limited to ±1MB; b is ±128MB. In very large functions the
          # true-target can be far, so we always route the far jump through b.
          skip_lbl = "#{func_local(instr.true_label)}_cjskip#{@cond_skip_seq += 1}"
          emit "  cbz  x9, #{skip_lbl}"
          emit "  b    #{func_local(instr.true_label)}"
          emit "#{skip_lbl}:"
          emit "  b    #{func_local(instr.false_label)}"

        when IR::Return
          if instr.value
            func_is_fp = @mod.fp_funcs.include?(@func.name)
            if fp_operand?(instr.value) || func_is_fp
              load_fp_operand(instr.value, 'd0')
            else
              load_operand(instr.value, 'x0')
              # Truncate narrow unsigned return values so callers see wrapping semantics.
              # (OCC arithmetic uses 64-bit registers; unsigned 32/16/8-bit overflow must wrap.)
              rt = @func.return_type
              if rt.is_a?(OCC::Types::IntegerType) && !rt.signed?
                case rt.size.to_i
                when 4 then emit '  ubfx x0, x0, #0, #32'
                when 2 then emit '  ubfx x0, x0, #0, #16'
                when 1 then emit '  ubfx x0, x0, #0, #8'
                end
              end
            end
          end
          # Epilogue
          frame_sz = @frame_sz
          emit '  mov sp, x29'
          if frame_sz <= 504
            emit "  ldp x29, x30, [sp], ##{frame_sz}"
          else
            emit '  ldp x29, x30, [sp]'
            emit_sp_add(frame_sz)
          end
          emit '  ret'

        when IR::Cast
          if fp_operand?(instr.src) && fp_ctype?(instr.type)
            # FP → FP: float→double widening or no-op
            load_fp_operand(instr.src, 'd9')
            store_fp_temp(instr.dst, 'd9')
          elsif fp_operand?(instr.src) && !fp_ctype?(instr.type)
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
            # int → int: truncate/extend to target width
            load_operand(instr.src, 'x9')
            ct = instr.type
            if ct.is_a?(OCC::Types::IntegerType)
              case ct.size
              when 1
                emit(ct.signed? ? '  sxtb x9, w9' : '  and x9, x9, #0xff')
              when 2
                emit(ct.signed? ? '  sxth x9, w9' : '  and x9, x9, #0xffff')
              when 4
                emit(ct.signed? ? '  sxtw x9, w9' : '  ubfx x9, x9, #0, #32')
              end
            end
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
        when :udiv
          emit '  udiv x9, x9, x10'
        when :percent
          emit '  sdiv x11, x9, x10'
          emit '  msub x9, x11, x10, x9'
        when :umod
          emit '  udiv x11, x9, x10'
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
        when :urshift
          emit '  lsr x9, x9, x10'
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
        when :ult
          emit '  cmp x9, x10'
          emit '  cset x9, lo'
        when :ugt
          emit '  cmp x9, x10'
          emit '  cset x9, hi'
        when :uleq
          emit '  cmp x9, x10'
          emit '  cset x9, ls'
        when :ugeq
          emit '  cmp x9, x10'
          emit '  cset x9, hs'
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

        # Truncate unsigned 32-bit (and smaller) arithmetic results so overflow wraps correctly.
        # OCC uses 64-bit registers; e.g. uint32_t(1)+uint32_t(UINT32_MAX) = 0x100000000 not 0.
        if instr.type.is_a?(OCC::Types::IntegerType) && !instr.type.signed? &&
           %i[plus minus star slash udiv percent umod amp pipe caret lshift rshift urshift].include?(instr.op)
          case instr.type.size.to_i
          when 4 then emit '  ubfx x9, x9, #0, #32'
          when 2 then emit '  ubfx x9, x9, #0, #16'
          when 1 then emit '  ubfx x9, x9, #0, #8'
          end
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
        when :lt, :ult
          emit '  fcmp d9, d10'; emit '  cset x9, mi'
          store_temp(instr.dst, 'x9'); return
        when :leq, :uleq
          emit '  fcmp d9, d10'; emit '  cset x9, ls'
          store_temp(instr.dst, 'x9'); return
        when :gt, :ugt
          emit '  fcmp d9, d10'; emit '  cset x9, gt'
          store_temp(instr.dst, 'x9'); return
        when :geq, :ugeq
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
          emit_addr_from_fp('x9', @frame_sz)
          store_temp(instr.dst, 'x9')
          return
        end

        # ── GCC bit-manipulation builtins — emitted inline ───────────────────
        if func_ref.is_a?(IR::GlobalRef)
          case func_ref.name
          when '__builtin_clz'
            # 32-bit: count leading zeros of lower 32 bits
            load_operand(args[0], 'x9')
            emit '  clz w9, w9'
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_clzl', '__builtin_clzll'
            load_operand(args[0], 'x9')
            emit '  clz x9, x9'
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_ctz'
            load_operand(args[0], 'x9')
            emit '  rbit w9, w9'
            emit '  clz  w9, w9'
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_ctzl', '__builtin_ctzll'
            load_operand(args[0], 'x9')
            emit '  rbit x9, x9'
            emit '  clz  x9, x9'
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_popcount', '__builtin_popcountl', '__builtin_popcountll'
            load_operand(args[0], 'x9')
            emit '  fmov d9, x9'
            emit '  cnt  v9.8b, v9.8b'
            emit '  addv b9, v9.8b'
            emit '  fmov w9, s9'
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_bswap32'
            load_operand(args[0], 'x9')
            emit '  rev w9, w9'
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_bswap64'
            load_operand(args[0], 'x9')
            emit '  rev x9, x9'
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_ia32_bsf32', '__builtin_ia32_bsf64'
            # x86 bit-scan forward — same as ctz on ARM64
            load_operand(args[0], 'x9')
            emit '  rbit x9, x9'
            emit '  clz  x9, x9'
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_add_overflow'
            load_operand(args[0], 'x9')
            load_operand(args[1], 'x10')
            load_operand(args[2], 'x11')
            emit '  adds x9, x9, x10'
            emit '  str  x9, [x11]'
            emit '  cset x9, cs'      # unsigned carry = overflow
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_sub_overflow'
            load_operand(args[0], 'x9')
            load_operand(args[1], 'x10')
            load_operand(args[2], 'x11')
            emit '  subs x9, x9, x10'
            emit '  str  x9, [x11]'
            emit '  cset x9, cc'      # carry clear = unsigned borrow
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_mul_overflow'
            load_operand(args[0], 'x9')
            load_operand(args[1], 'x10')
            load_operand(args[2], 'x11')
            emit '  mul  x12, x9, x10'
            emit '  umulh x9, x9, x10'   # high 64 bits; nonzero = overflow
            emit '  str  x12, [x11]'
            emit '  cmp  x9, #0'
            emit '  cset x9, ne'
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_alloca'
            # Allocate `size` bytes on the stack; align up to 16 bytes
            load_operand(args[0], 'x9')
            emit '  add  x9, x9, #15'
            emit '  and  x9, x9, #-16'
            emit '  sub  sp, sp, x9'
            emit '  mov  x9, sp'
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_assume_aligned'
            # Alignment hint only — return the pointer unchanged
            load_operand(args[0], 'x9')
            store_temp(instr.dst, 'x9')
            return
          when '__builtin_prefetch'
            # Memory prefetch hint — no-op on ARM64 (prfm requires literal hint)
            return
          end
        end

        # Variadic functions: named args in x0..x{N-1}, variadic args on stack
        named_count = func_ref.is_a?(IR::GlobalRef) ?
                        @mod.variadic_funcs[func_ref.name] : nil
        variadic = !named_count.nil?

        if variadic
          named_args = args.first(named_count)
          var_args   = args.drop(named_count)
          stack_sz   = 0

          # Push variadic args to the stack FIRST so that any TLS bootstrap calls
          # inside load_operand don't clobber named-arg registers (x0..xN) already set.
          if var_args.any?
            stack_sz = align16(var_args.length * 8)
            emit_sp_sub(stack_sz)
            var_args.each_with_index do |a, i|
              load_operand(a, 'x9')
              emit "  str x9, [sp, ##{i * 8}]"
            end
          end

          # Load named args into x0..x{N-1} after variadic stack is committed
          int_idx = 0
          named_args.each do |a|
            load_operand(a, ARG_REGS[int_idx])
            int_idx += 1
          end

          emit "  bl #{sym(func_ref.name)}"
          emit_sp_add(stack_sz) if var_args.any?
        else
          # Non-variadic: integer args in x0-x7, FP args in d0-d7.
          # Args beyond the 8th integer slot are passed on the stack (AAPCS64).
          int_count = args.count { |a| !fp_operand?(a) }
          extra_int  = [int_count - ARG_REGS.length, 0].max
          call_stack_sz = extra_int > 0 ? align16(extra_int * 8) : 0
          emit_sp_sub(call_stack_sz) if call_stack_sz > 0

          int_idx = 0
          fp_idx  = 0
          stack_idx = 0
          args.each do |a|
            if fp_operand?(a)
              load_fp_operand(a, "d#{fp_idx}") if fp_idx < 8
              fp_idx += 1
            else
              if int_idx < ARG_REGS.length
                load_operand(a, ARG_REGS[int_idx])
              else
                load_operand(a, 'x9')
                emit "  str x9, [sp, ##{stack_idx * 8}]"
                stack_idx += 1
              end
              int_idx += 1
            end
          end
          case func_ref
          when IR::GlobalRef
            if @mod.func_names.include?(func_ref.name) || !@mod.globals.key?(func_ref.name)
              emit "  bl #{sym(func_ref.name)}"
            else
              load_operand(func_ref, 'x9')
              emit '  blr x9'
            end
          when IR::Temp
            load_operand(func_ref, 'x9')
            emit '  blr x9'
          end
          emit_sp_add(call_stack_sz) if call_stack_sz > 0
        end

        # Capture return value
        func_name = func_ref.is_a?(IR::GlobalRef) ? func_ref.name : nil
        if @mod.fp_funcs.include?(func_name) || fp_ctype?(instr.type)
          store_fp_temp(instr.dst, 'd0')
        else
          # Normalise narrow integer returns to consistent 64-bit representations.
          # Signed: sign-extend (libc returns w0; OCC returns full x0 — sxtw/sxth/sxtb handles both).
          # Unsigned: zero-extend upper bits — OCC arithmetic may leave overflow bits set (e.g.
          # safe_add_uint32(1, UINT32_MAX) computes 0x100000000; ubfx truncates to correct 0).
          if instr.type.is_a?(OCC::Types::IntegerType) && instr.type.size.to_i < 8
            if instr.type.signed?
              case instr.type.size.to_i
              when 4 then emit '  sxtw x0, w0'
              when 2 then emit '  sxth x0, w0'
              when 1 then emit '  sxtb x0, w0'
              end
            else
              case instr.type.size.to_i
              when 4 then emit '  ubfx x0, x0, #0, #32'
              when 2 then emit '  ubfx x0, x0, #0, #16'
              when 1 then emit '  ubfx x0, x0, #0, #8'
              end
            end
          end
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
        sz_aligned = (sz + 7) / 8 * 8  # advance slot_next by aligned size to avoid gaps
        @slot_next = ((@slot_next + 7) / 8 * 8)
        offset = @slot_next + 16   # +16 so first slot is at fp+16
        @slot_next += sz_aligned
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

      # ldr/str [x29, #N] encodes N as a scaled unsigned 12-bit immediate (0..32760 for 8-byte).
      # For larger offsets, compute the address explicitly using x16 (intra-procedure scratch).
      def emit_slot_load(reg, slot)
        if slot <= 32_760
          emit "  ldr #{reg}, [x29, ##{slot}]"
        else
          emit_addr_from_fp('x16', slot)
          emit "  ldr #{reg}, [x16]"
        end
      end

      def emit_slot_store(reg, slot)
        if slot <= 32_760
          emit "  str #{reg}, [x29, ##{slot}]"
        else
          emit_addr_from_fp('x16', slot)
          emit "  str #{reg}, [x16]"
        end
      end

      def emit_fp_slot_load(reg, slot)
        if slot <= 32_760
          emit "  ldr #{reg}, [x29, ##{slot}]"
        else
          emit_addr_from_fp('x16', slot)
          emit "  ldr #{reg}, [x16]"
        end
      end

      def emit_fp_slot_store(reg, slot)
        if slot <= 32_760
          emit "  str #{reg}, [x29, ##{slot}]"
        else
          emit_addr_from_fp('x16', slot)
          emit "  str #{reg}, [x16]"
        end
      end

      # Emit `reg = x29 + offset`, handling offsets > 4095 (ARM64 add-imm limit).
      def emit_addr_from_fp(reg, offset)
        if offset <= 4095
          emit "  add #{reg}, x29, ##{offset}"
        else
          emit "  mov #{reg}, #0x#{(offset & 0xFFFF).to_s(16)}"
          emit "  movk #{reg}, #0x#{((offset >> 16) & 0xFFFF).to_s(16)}, lsl #16" unless (offset >> 16).zero?
          emit "  add #{reg}, x29, #{reg}"
        end
      end

      # Width-appropriate load from a stack slot into x10.
      # Uses x28 as scratch when the slot exceeds the instruction's immediate limit.
      def emit_alloca_load(slot, sz, signed)
        max_imm = 4095 * [sz, 8].min
        if slot <= max_imm
          base = "[x29, ##{slot}]"
        else
          emit_addr_from_fp('x28', slot)
          base = '[x28]'
        end
        case sz
        when 1 then emit(signed ? "  ldrsb x10, #{base}" : "  ldrb w10, #{base}")
        when 2 then emit(signed ? "  ldrsh x10, #{base}" : "  ldrh w10, #{base}")
        when 4 then emit(signed ? "  ldrsw x10, #{base}" : "  ldr w10, #{base}")
        else        emit "  ldr x10, #{base}"
        end
      end

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
          emit_slot_load(reg, slot)
        when IR::GlobalRef
          if @mod.tls_globals.key?(op.name)
            # Thread-local variable: use TLV descriptor access
            emit_tls_load(op.name, reg)
          elsif @mod.func_names.include?(op.name)
            if @mod.defined_funcs.include?(op.name)
              # Locally-defined function: direct PC-relative address
              emit "  adrp #{reg}, #{sym(op.name)}@PAGE"
              emit "  add  #{reg}, #{reg}, #{sym(op.name)}@PAGEOFF"
            else
              # External/dylib function: GOT indirection gives function address
              emit "  adrp #{reg}, #{sym(op.name)}@GOTPAGE"
              emit "  ldr  #{reg}, [#{reg}, #{sym(op.name)}@GOTPAGEOFF]"
            end
          elsif @mod.globals.key?(op.name)
            # Locally-defined data global: direct page-relative load with correct width
            g_type = @mod.globals[op.name][:type]&.unqualified
            g_sz   = (g_type.respond_to?(:size) ? g_type.size : 8 rescue 8)
            signed = g_type.is_a?(OCC::Types::IntegerType) && g_type.signed?
            wreg   = reg.start_with?('x') ? "w#{reg[1..]}" : reg
            emit "  adrp #{reg}, #{sym(op.name)}@PAGE"
            case g_sz
            when 1
              emit(signed ? "  ldrsb #{reg}, [#{reg}, #{sym(op.name)}@PAGEOFF]"
                          : "  ldrb #{wreg}, [#{reg}, #{sym(op.name)}@PAGEOFF]")
            when 2
              emit(signed ? "  ldrsh #{reg}, [#{reg}, #{sym(op.name)}@PAGEOFF]"
                          : "  ldrh #{wreg}, [#{reg}, #{sym(op.name)}@PAGEOFF]")
            when 4
              emit(signed ? "  ldrsw #{reg}, [#{reg}, #{sym(op.name)}@PAGEOFF]"
                          : "  ldr  #{wreg}, [#{reg}, #{sym(op.name)}@PAGEOFF]")
            else
              emit "  ldr  #{reg}, [#{reg}, #{sym(op.name)}@PAGEOFF]"
            end
          else
            # Extern/dylib data global: GOT gives address of variable, then load value
            emit "  adrp #{reg}, #{sym(op.name)}@GOTPAGE"
            emit "  ldr  #{reg}, [#{reg}, #{sym(op.name)}@GOTPAGEOFF]"
            emit "  ldr  #{reg}, [#{reg}]"
          end
        when IR::StringRef
          emit "  adrp #{reg}, l_str_#{op.id}@PAGE"
          emit "  add  #{reg}, #{reg}, l_str_#{op.id}@PAGEOFF"
        end
      end

      def store_temp(temp, reg)
        slot = alloc_slot_for(temp)
        emit_slot_store(reg, slot)
      end

      def emit_struct_copy(src, dst, size)
        # For large structs, call memcpy rather than emitting hundreds of inline
        # ldp/stp pairs. Calling convention: x9=src, x10=dst at all call sites.
        if size > 256
          emit "  mov x0, #{dst}"
          emit "  mov x1, #{src}"
          emit_mov_imm('x2', size)
          emit "  bl #{sym('memcpy')}"
          return
        end

        offset = 0
        remaining = size
        src_base = src
        dst_base = dst

        while remaining >= 16
          # ldp signed offset must be in [-512, 504] aligned to 8. When we're
          # about to exceed this range, bump the base registers forward.
          if offset > 488
            emit "  add x13, #{src_base}, ##{offset}"
            emit "  add x14, #{dst_base}, ##{offset}"
            src_base = 'x13'
            dst_base = 'x14'
            offset = 0
          end
          emit "  ldp x11, x12, [#{src_base}, ##{offset}]"
          emit "  stp x11, x12, [#{dst_base}, ##{offset}]"
          offset += 16
          remaining -= 16
        end
        # For the tail, ldr/str unsigned offset supports up to 32760 for 64-bit,
        # but after bumping we may have a large leftover offset too. Bump if needed.
        if offset > 255
          emit "  add x13, #{src_base}, ##{offset}"
          emit "  add x14, #{dst_base}, ##{offset}"
          src_base = 'x13'
          dst_base = 'x14'
          offset = 0
        end
        if remaining >= 8
          emit "  ldr x11, [#{src_base}, ##{offset}]"
          emit "  str x11, [#{dst_base}, ##{offset}]"
          offset += 8
          remaining -= 8
        end
        if remaining >= 4
          emit "  ldr w11, [#{src_base}, ##{offset}]"
          emit "  str w11, [#{dst_base}, ##{offset}]"
          offset += 4
          remaining -= 4
        end
        if remaining >= 2
          emit "  ldrh w11, [#{src_base}, ##{offset}]"
          emit "  strh w11, [#{dst_base}, ##{offset}]"
          offset += 2
          remaining -= 2
        end
        if remaining > 0
          emit "  ldrb w11, [#{src_base}, ##{offset}]"
          emit "  strb w11, [#{dst_base}, ##{offset}]"
        end
      end

      # Fill size bytes at [dst] with the low byte of val_reg.
      def emit_struct_fill(val_reg, dst, size)
        # For large zero-fills, call memset rather than emitting inline stores.
        if size > 256
          emit "  mov x0, #{dst}"
          emit "  mov x1, #{val_reg}"
          emit_mov_imm('x2', size)
          emit "  bl #{sym('memset')}"
          return
        end

        offset = 0
        remaining = size
        dst_base = dst
        while remaining >= 16
          if offset > 488
            emit "  add x14, #{dst_base}, ##{offset}"
            dst_base = 'x14'
            offset = 0
          end
          emit "  stp #{val_reg}, #{val_reg}, [#{dst_base}, ##{offset}]"
          offset += 16
          remaining -= 16
        end
        if offset > 255
          emit "  add x14, #{dst_base}, ##{offset}"
          dst_base = 'x14'
          offset = 0
        end
        if remaining >= 8
          emit "  str #{val_reg}, [#{dst_base}, ##{offset}]"
          offset += 8
          remaining -= 8
        end
        if remaining >= 4
          emit "  str w#{val_reg[1..]}, [#{dst_base}, ##{offset}]"
          offset += 4
          remaining -= 4
        end
        if remaining >= 2
          emit "  strh w#{val_reg[1..]}, [#{dst_base}, ##{offset}]"
          offset += 2
          remaining -= 2
        end
        emit "  strb w#{val_reg[1..]}, [#{dst_base}, ##{offset}]" if remaining > 0
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

      # Emit `sub sp, sp, #n` or `add sp, sp, #n` handling n > 4095 via x16.
      def emit_sp_sub(n)
        if n <= 4095
          emit "  sub sp, sp, ##{n}"
        else
          emit_mov_x16(n)
          emit '  sub sp, sp, x16'
        end
      end

      def emit_sp_add(n)
        if n <= 4095
          emit "  add sp, sp, ##{n}"
        else
          emit_mov_x16(n)
          emit '  add sp, sp, x16'
        end
      end

      # Load a 64-bit immediate into any register using movz/movk.
      def emit_mov_imm(reg, val)
        chunks = [val & 0xFFFF, (val >> 16) & 0xFFFF, (val >> 32) & 0xFFFF, (val >> 48) & 0xFFFF]
        first = true
        chunks.each_with_index do |c, i|
          next if c.zero? && !first
          if first
            emit "  movz #{reg}, ##{c}#{i > 0 ? ", lsl ##{i * 16}" : ''}"
            first = false
          else
            emit "  movk #{reg}, ##{c}, lsl ##{i * 16}"
          end
        end
        emit "  movz #{reg}, #0" if first
      end

      # Load a 64-bit immediate into x16 using movz/movk.
      def emit_mov_x16(val)
        chunks = [val & 0xFFFF, (val >> 16) & 0xFFFF, (val >> 32) & 0xFFFF, (val >> 48) & 0xFFFF]
        first = true
        chunks.each_with_index do |c, i|
          next if c.zero? && !first
          if first
            emit "  movz x16, ##{c}#{i > 0 ? ", lsl ##{i * 16}" : ''}"
            first = false
          else
            emit "  movk x16, ##{c}, lsl ##{i * 16}"
          end
        end
        emit '  movz x16, #0' if first  # val == 0 edge case
      end
    end
  end
end
