# frozen_string_literal: true

module OCC
  module Types
    # ── Base ───────────────────────────────────────────────────────────────────

    class CType
      def pointer?  = false
      def array?    = false
      def function? = false
      def struct?   = false
      def union?    = false
      def enum?     = false
      def integer?  = false
      def floating? = false
      def arithmetic? = integer? || floating?
      def scalar?   = arithmetic? || pointer?
      def void?     = false
      def complete? = true
      def qualifiers = []
      def unqualified = self

      def ==(other) = other.class == self.class
    end

    # ── Void ──────────────────────────────────────────────────────────────────

    class VoidType < CType
      def void?    = true
      def complete? = false
      def size     = raise TypeError, 'sizeof(void) is not defined'
      def align    = raise TypeError, 'alignof(void) is not defined'
      def to_s     = 'void'
    end

    VOID = VoidType.new.freeze

    # ── Boolean ───────────────────────────────────────────────────────────────

    class BoolType < CType
      def integer? = true
      def signed?  = false
      def size     = 1
      def align    = 1
      def rank     = 0
      def to_s     = '_Bool'
    end

    BOOL = BoolType.new.freeze

    # ── Integer types ──────────────────────────────────────────────────────────

    class IntegerType < CType
      attr_reader :name, :size, :align, :rank, :signed

      def initialize(name, size, align, rank, signed)
        @name  = name; @size = size; @align = align
        @rank  = rank; @signed = signed
      end

      def integer? = true
      def signed?  = @signed
      def unsigned? = !@signed
      def to_s     = @name
      def ==(other) = other.is_a?(IntegerType) && other.name == @name
    end

    CHAR       = IntegerType.new('char',           1, 1, 1, true).freeze
    SCHAR      = IntegerType.new('signed char',    1, 1, 1, true).freeze
    UCHAR      = IntegerType.new('unsigned char',  1, 1, 1, false).freeze
    SHORT      = IntegerType.new('short',          2, 2, 2, true).freeze
    USHORT     = IntegerType.new('unsigned short', 2, 2, 2, false).freeze
    INT        = IntegerType.new('int',            4, 4, 3, true).freeze
    UINT       = IntegerType.new('unsigned int',   4, 4, 3, false).freeze
    LONG       = IntegerType.new('long',           8, 8, 4, true).freeze
    ULONG      = IntegerType.new('unsigned long',  8, 8, 4, false).freeze
    LONGLONG   = IntegerType.new('long long',      8, 8, 5, true).freeze
    ULONGLONG  = IntegerType.new('unsigned long long', 8, 8, 5, false).freeze

    # ── Floating-point types ───────────────────────────────────────────────────

    class FloatingType < CType
      attr_reader :name, :size, :align

      def initialize(name, size, align)
        @name = name; @size = size; @align = align
      end

      def floating? = true
      def to_s      = @name
      def ==(other) = other.is_a?(FloatingType) && other.name == @name
    end

    FLOAT       = FloatingType.new('float',       4, 4).freeze
    DOUBLE      = FloatingType.new('double',      8, 8).freeze
    LONGDOUBLE  = FloatingType.new('long double', 16, 16).freeze

    # ── Pointer ───────────────────────────────────────────────────────────────

    class PointerType < CType
      attr_reader :base, :qualifiers

      def initialize(base, qualifiers = [])
        @base = base; @qualifiers = qualifiers
      end

      def pointer? = true
      def size     = 8   # 64-bit
      def align    = 8
      def to_s     = "#{@base} *"
      def ==(other) = other.is_a?(PointerType) && other.base == @base
    end

    # ── Array ─────────────────────────────────────────────────────────────────

    class ArrayType < CType
      attr_reader :element, :count

      def initialize(element, count)
        @element = element; @count = count
      end

      def array?    = true
      def complete? = !@count.nil?
      def size      = @element.size * @count
      def align     = @element.align
      def to_s      = "#{@element}[#{@count}]"
      def ==(other) = other.is_a?(ArrayType) && other.element == @element && other.count == @count
    end

    # ── Function ──────────────────────────────────────────────────────────────

    class FunctionType < CType
      attr_reader :return_type, :params, :variadic

      def initialize(return_type, params, variadic: false)
        @return_type = return_type; @params = params; @variadic = variadic
      end

      def function? = true
      def complete? = false
      def to_s
        ps = @params.map { |p| p[:type].to_s }.join(', ')
        ps += ', ...' if @variadic
        "#{@return_type}(#{ps})"
      end
    end

    # ── Struct / union ─────────────────────────────────────────────────────────

    class StructType < CType
      attr_reader :keyword, :tag
      attr_accessor :fields, :pack   # pack: nil (natural) or Integer (max field alignment)

      def initialize(keyword, tag)
        @keyword = keyword; @tag = tag; @fields = nil; @pack = nil
      end

      def struct? = @keyword == :kw_struct
      def union?  = @keyword == :kw_union
      def complete? = !@fields.nil?

      def size
        return raise TypeError, "incomplete #{@keyword} #{@tag}" unless complete?
        raw = if @keyword == :kw_union
          @fields.map { |f| f[:type].size rescue 0 }.max || 0
        else
          # Flexible array members (unsized arrays) contribute 0 to struct size — exclude them.
          sized = @fields.reject { |f| f[:type].is_a?(ArrayType) && f[:type].count.nil? }
          if sized.last
            last = sized.last
            # For bitfields: use unit_size (the actual bytes consumed in the
            # storage unit or packed group) rather than the underlying type size.
            last_sz = (last[:bit_width] && last[:unit_size]) ? last[:unit_size] : (last[:type].size rescue 4)
            last[:offset] + last_sz
          else
            0
          end
        end
        # Add tail padding so sizeof(struct/union) is a multiple of its alignment (C standard).
        al = self.align
        al > 1 ? ((raw + al - 1) / al * al) : raw
      end

      def align
        return 1 unless complete? && !@fields.empty?
        natural = @fields.map { |f| f[:type].align }.max
        @pack ? [@pack, natural].min : natural
      end

      def to_s = "#{@keyword == :kw_struct ? 'struct' : 'union'} #{@tag}"
    end

    # ── Enum ───────────────────────────────────────────────────────────────────

    class EnumType < CType
      attr_reader :tag
      attr_accessor :enumerators  # {name => int_value}

      def initialize(tag)
        @tag = tag; @enumerators = nil
      end

      def integer?  = true
      def signed?   = true
      def complete? = !@enumerators.nil?
      def size      = 4
      def align     = 4
      def rank      = INT.rank
      def to_s      = "enum #{@tag}"
    end

    # ── Qualified type ────────────────────────────────────────────────────────

    class QualifiedType < CType
      attr_reader :base, :qualifiers

      def initialize(base, qualifiers)
        @base = base; @qualifiers = qualifiers
      end

      def unqualified = @base
      def method_missing(m, *a, &b) = @base.respond_to?(m) ? @base.send(m, *a, &b) : super
      def respond_to_missing?(m, *a) = @base.respond_to?(m) || super
      def to_s = "#{@qualifiers.join(' ')} #{@base}"
    end

    # ── Usual arithmetic conversions (C11 6.3.1.8) ────────────────────────────

    def self.usual_arithmetic_conversion(t1, t2)
      t1 = t1.unqualified
      t2 = t2.unqualified

      # Pointer arithmetic: pointer ± integer → pointer
      return t1 if t1.is_a?(PointerType) && t2.integer?
      return t2 if t2.is_a?(PointerType) && t1.integer?
      # Pointer difference: pointer - pointer → ptrdiff_t (LONG)
      return LONG if t1.is_a?(PointerType) && t2.is_a?(PointerType)

      return LONGDOUBLE if [t1, t2].any? { |t| t == LONGDOUBLE }
      return DOUBLE     if [t1, t2].any? { |t| t == DOUBLE }
      return FLOAT      if [t1, t2].any? { |t| t == FLOAT }

      # Non-integer non-pointer: bail out (guard before calling signed? below)
      return t1 unless t1.respond_to?(:signed?) && t2.respond_to?(:signed?)

      t1 = integer_promote(t1)
      t2 = integer_promote(t2)

      return t1 if t1 == t2

      if t1.signed? == t2.signed?
        t1.rank >= t2.rank ? t1 : t2
      elsif !t1.signed? && t1.rank >= t2.rank
        t1
      elsif !t2.signed? && t2.rank >= t1.rank
        t2
      elsif t1.signed? && t1.size > t2.size
        t1
      elsif t2.signed? && t2.size > t1.size
        t2
      else
        t1.signed? ? unsigned_of(t1) : unsigned_of(t2)
      end
    end

    def self.integer_promote(type)
      return type unless type.integer?
      return type if type.rank >= INT.rank
      # types narrower than int are promoted to int (or unsigned int if they can't fit)
      type.size < INT.size ? INT : type
    end

    def self.unsigned_of(type)
      case type
      when INT      then UINT
      when LONG     then ULONG
      when LONGLONG then ULONGLONG
      else type
      end
    end

    # ── Type from AST specifiers ───────────────────────────────────────────────

    def self.from_specifiers(spec)
      kws = spec.type_keywords

      if spec.tag_decl.is_a?(OCC::AST::StructSpec)
        return StructType.new(spec.tag_decl.keyword, spec.tag_decl.tag)
      end
      if spec.tag_decl.is_a?(OCC::AST::EnumSpec)
        return EnumType.new(spec.tag_decl.tag)
      end
      return INT if kws.empty? && spec.typedef_name.nil?   # implicit int

      kws_set = kws.sort.map(&:to_s)

      case kws_set
      when ['void']                         then VOID
      when ['bool'], ['_Bool']              then BOOL
      when ['char']                         then CHAR
      when ['char', 'signed']               then SCHAR
      when ['char', 'unsigned']             then UCHAR
      when ['short'], ['int', 'short'],
           ['short', 'signed'], ['int', 'short', 'signed'] then SHORT
      when ['short', 'unsigned'],
           ['int', 'short', 'unsigned']     then USHORT
      when ['int'], ['signed'], ['int', 'signed'] then INT
      when ['unsigned'], ['int', 'unsigned'] then UINT
      when ['long'], ['int', 'long'],
           ['long', 'signed'], ['int', 'long', 'signed'] then LONG
      when ['long', 'unsigned'],
           ['int', 'long', 'unsigned']      then ULONG
      when ['long', 'long'], ['int', 'long', 'long'],
           ['long', 'long', 'signed'], ['int', 'long', 'long', 'signed'] then LONGLONG
      when ['long', 'long', 'unsigned'],
           ['int', 'long', 'long', 'unsigned']                           then ULONGLONG
      when ['double', 'float']              then raise TypeError, 'invalid type'
      when ['float']                        then FLOAT
      when ['double']                       then DOUBLE
      when ['double', 'long']               then LONGDOUBLE
      when ['__int128'], ['__int128', 'signed'] then LONGLONG
      when ['__int128', 'unsigned']         then ULONGLONG
      else
        # Fallback: if typedef_name is set, use INT as placeholder;
        # the semantic analyser resolves typedef names via the symbol table.
        spec.typedef_name ? INT : INT
      end
    end

    # Apply qualifiers from a TypeSpec to a base type.
    def self.apply_qualifiers(base, spec)
      quals = spec.qualifiers
      quals.empty? ? base : QualifiedType.new(base, quals)
    end
  end
end
