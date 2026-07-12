# frozen_string_literal: true

require 'set'
require 'time'

module OCC
  # A source-level C preprocessor.
  #
  # Processes directives line-by-line and expands macros in ordinary source
  # lines, producing expanded source text for the Lexer.
  class Preprocessor
    PREDEFINED = {
      '__STDC__'             => '1',
      '__STDC_VERSION__'     => '201112L',
      '__STDC_HOSTED__'      => '1'
    }.freeze

    def initialize(source, filename, include_paths: [], framework_paths: [], defines: {}, target: nil)
      @filename        = filename
      @include_paths   = include_paths
      @framework_paths = framework_paths
      @macros          = {}
      @once_files    = Set.new      # files seen via #pragma once
      @include_stack = [filename]   # guard against recursive includes
      @include_depth = 0            # 0 = main file, >0 = inside an include

      PREDEFINED.each { |k, v| define_object_macro(k, v) }
      # Date/time macros – set once at instantiation
      now = Time.now
      define_object_macro('__DATE__', %("#{now.strftime('%b %e %Y')}"))
      define_object_macro('__TIME__', %("#{now.strftime('%H:%M:%S')}"))

      # Architecture/OS predefined macros (used by stdarg.h, sys/types.h, etc.)
      tgt = target || begin
        arch = `uname -m`.strip rescue ''
        os   = `uname -s`.strip rescue ''
        case [arch, os]
        when ['arm64',  'Darwin'] then :arm64_macos
        when ['x86_64', 'Darwin'] then :amd64_macos
        else :amd64_linux
        end
      end
      case tgt
      when :arm64_macos
        define_object_macro('__aarch64__',      '1')
        define_object_macro('__arm64__',        '1')
        define_object_macro('__APPLE__',        '1')
        define_object_macro('__MACH__',         '1')
        define_object_macro('__LITTLE_ENDIAN__','1')
        define_object_macro('__LP64__',         '1')
        define_object_macro('__SIZEOF_POINTER__','8')
        define_object_macro('__POINTER_WIDTH__','64')
        define_object_macro('__INTPTR_WIDTH__', '64')
        define_object_macro('__SIZEOF_LONG__',  '8')
        define_object_macro('__LONG_MAX__',     '9223372036854775807L')
      when :amd64_macos
        define_object_macro('__x86_64__',       '1')
        define_object_macro('__APPLE__',        '1')
        define_object_macro('__MACH__',         '1')
        define_object_macro('__LITTLE_ENDIAN__','1')
        define_object_macro('__LP64__',         '1')
        define_object_macro('__SIZEOF_POINTER__','8')
        define_object_macro('__POINTER_WIDTH__','64')
        define_object_macro('__INTPTR_WIDTH__', '64')
        define_object_macro('__SIZEOF_LONG__',  '8')
        define_object_macro('__LONG_MAX__',     '9223372036854775807L')
      else
        define_object_macro('__x86_64__',       '1')
        define_object_macro('__linux__',        '1')
        define_object_macro('__LITTLE_ENDIAN__','1')
        define_object_macro('__LP64__',         '1')
        define_object_macro('__SIZEOF_POINTER__','8')
        define_object_macro('__POINTER_WIDTH__','64')
        define_object_macro('__INTPTR_WIDTH__', '64')
        define_object_macro('__SIZEOF_LONG__',  '8')
        define_object_macro('__LONG_MAX__',     '9223372036854775807L')
      end

      # GCC/Clang compiler extension macros — silently consumed by expansion
      define_object_macro('__extension__',       '')
      define_object_macro('__inline__',          'inline')
      define_object_macro('__inline',            'inline')
      define_object_macro('__const__',           'const')
      define_object_macro('__volatile__',        'volatile')
      define_object_macro('__restrict__',        'restrict')
      define_object_macro('__restrict',          'restrict')
      define_object_macro('__signed__',          'signed')
      define_object_macro('__func__',            '"<func>"')
      define_object_macro('__FUNCTION__',        '"<func>"')
      define_object_macro('__PRETTY_FUNCTION__', '"<func>"')
      define_object_macro('__GNUC__',            '4')
      define_object_macro('__GNUC_MINOR__',      '2')
      define_object_macro('__GNUC_PATCHLEVEL__', '1')
      define_object_macro('__builtin_va_list',   'char*')
      define_object_macro('__thread',            '_Thread_local')
      define_object_macro('__int128_t',          '__int128')
      define_object_macro('__uint128_t',         'unsigned __int128')
      # Function-like extension macros
      @macros['__attribute__']         = { kind: :function, params: ['x'], variadic: false, body: '' }
      @macros['__attribute']           = { kind: :function, params: ['x'], variadic: false, body: '' }
      @macros['__declspec']            = { kind: :function, params: ['x'], variadic: false, body: '' }
      @macros['__builtin_expect']       = { kind: :function, params: ['expr', 'val'], variadic: false, body: 'expr' }
      @macros['__builtin_unreachable']  = { kind: :function, params: [], variadic: true, body: '' }
      @macros['__builtin_constant_p']   = { kind: :function, params: ['x'], variadic: false, body: '0' }

      # C11 atomic memory-order constants (we treat atomics as non-atomic)
      @macros['__ATOMIC_RELAXED']  = { kind: :object, body: '0' }
      @macros['__ATOMIC_CONSUME']  = { kind: :object, body: '1' }
      @macros['__ATOMIC_ACQUIRE']  = { kind: :object, body: '2' }
      @macros['__ATOMIC_RELEASE']  = { kind: :object, body: '3' }
      @macros['__ATOMIC_ACQ_REL']  = { kind: :object, body: '4' }
      @macros['__ATOMIC_SEQ_CST']  = { kind: :object, body: '5' }
      # GCC atomic builtins — provide non-atomic fallback for single-threaded use
      @macros['__sync_bool_compare_and_swap'] = { kind: :function, params: ['ptr', 'old', 'new_val'], variadic: false,
                                                   body: '(*((ptr)) == (old) ? ((*((ptr)) = (new_val)), 1) : 0)' }
      @macros['__sync_val_compare_and_swap']  = { kind: :function, params: ['ptr', 'old', 'new_val'], variadic: false,
                                                   body: '(*((ptr)) == (old) ? ((*((ptr)) = (new_val)), (old)) : *((ptr)))' }
      # GCC __atomic_* builtins — non-atomic fallback (single-threaded semantics)
      @macros['__atomic_load_n']       = { kind: :function, params: ['ptr', 'ord'], variadic: false,
                                            body: '(*(ptr))' }
      @macros['__atomic_store_n']      = { kind: :function, params: ['ptr', 'val', 'ord'], variadic: false,
                                            body: '((*(ptr)) = (val))' }
      @macros['__atomic_exchange_n']   = { kind: :function, params: ['ptr', 'val', 'ord'], variadic: false,
                                            body: '(__extension__ ({ __typeof__(*(ptr)) __occ_xchg_old = *(ptr); *(ptr) = (val); __occ_xchg_old; }))' }
      @macros['__atomic_fetch_add']    = { kind: :function, params: ['ptr', 'val', 'ord'], variadic: false,
                                            body: '(__extension__ ({ __typeof__(*(ptr)) __occ_fa_old = *(ptr); *(ptr) += (val); __occ_fa_old; }))' }
      @macros['__atomic_add_fetch']    = { kind: :function, params: ['ptr', 'val', 'ord'], variadic: false,
                                            body: '(__extension__ ({ *(ptr) += (val); *(ptr); }))' }
      @macros['__atomic_fetch_sub']    = { kind: :function, params: ['ptr', 'val', 'ord'], variadic: false,
                                            body: '(__extension__ ({ __typeof__(*(ptr)) __occ_fs_old = *(ptr); *(ptr) -= (val); __occ_fs_old; }))' }
      @macros['__atomic_sub_fetch']    = { kind: :function, params: ['ptr', 'val', 'ord'], variadic: false,
                                            body: '(__extension__ ({ *(ptr) -= (val); *(ptr); }))' }
      @macros['__atomic_or_fetch']     = { kind: :function, params: ['ptr', 'val', 'ord'], variadic: false,
                                            body: '(__extension__ ({ *(ptr) |= (val); *(ptr); }))' }
      @macros['__atomic_and_fetch']    = { kind: :function, params: ['ptr', 'val', 'ord'], variadic: false,
                                            body: '(__extension__ ({ *(ptr) &= (val); *(ptr); }))' }
      @macros['__atomic_compare_exchange_n'] = { kind: :function,
                                            params: ['ptr', 'expected', 'desired', 'weak', 'suc', 'fail'],
                                            variadic: false,
                                            body: '(__extension__ ({ __typeof__(*(ptr)) __occ_cas_cur = *(ptr); int __occ_cas_eq = (__occ_cas_cur == *(expected)); if (__occ_cas_eq) { *(ptr) = (desired); } else { *(expected) = __occ_cas_cur; } __occ_cas_eq; }))' }
      # __asm__ and __asm are handled as keywords by the lexer (mapped to :kw_asm),
      # so they must NOT be defined as preprocessor macros here.
      # Type-checking builtins — return constants since we don't do compile-time type evaluation
      @macros['__builtin_types_compatible_p'] = { kind: :function, params: ['t1', 't2'], variadic: false, body: '0' }
      @macros['__builtin_choose_expr']  = { kind: :function, params: ['cond', 'then_e', 'else_e'], variadic: false, body: '(else_e)' }
      # Memory builtins — delegate to standard library functions
      @macros['__builtin_memcpy']  = { kind: :function, params: ['d', 's', 'n'], variadic: false, body: 'memcpy(d, s, n)' }
      @macros['__builtin_memset']  = { kind: :function, params: ['s', 'c', 'n'], variadic: false, body: 'memset(s, c, n)' }
      @macros['__builtin_memmove'] = { kind: :function, params: ['d', 's', 'n'], variadic: false, body: 'memmove(d, s, n)' }
      @macros['__builtin_memcmp']  = { kind: :function, params: ['s1', 's2', 'n'], variadic: false, body: 'memcmp(s1, s2, n)' }
      @macros['__builtin_strlen']  = { kind: :function, params: ['s'], variadic: false, body: 'strlen(s)' }
      @macros['__builtin_strcmp']  = { kind: :function, params: ['s1', 's2'], variadic: false, body: 'strcmp(s1, s2)' }
      @macros['__builtin_strcpy']  = { kind: :function, params: ['d', 's'], variadic: false, body: 'strcpy(d, s)' }
      @macros['_Pragma']               = { kind: :function, params: ['x'], variadic: false, body: '' }
      @macros['__has_attribute']       = { kind: :function, params: ['x'], variadic: false, body: '0' }
      @macros['__has_feature']         = { kind: :function, params: ['x'], variadic: false, body: '0' }
      @macros['__has_extension']       = { kind: :function, params: ['x'], variadic: false, body: '0' }
      @macros['__has_builtin']         = { kind: :function, params: ['x'], variadic: false, body: '0' }
      @macros['__has_include']         = { kind: :function, params: ['x'], variadic: false, body: '0' }

      # defines may be a Hash {name => value} or an Array of "NAME=VAL" strings
      case defines
      when Hash
        defines.each { |name, val| define_object_macro(name, val || '1') }
      when Array
        defines.each do |spec|
          name, val = spec.split('=', 2)
          define_object_macro(name, val || '1')
        end
      end

      @if_stack = []   # each entry: { active: bool, seen_true: bool }
      process_source(source, filename)
    end

    # Returns the fully-expanded source text.
    attr_reader :output

    def process
      # Strip any FROZEN/BLUE markers that survived expansion.
      @output.gsub(/[#{FROZEN_START}#{FROZEN_END}#{BLUE_START}#{BLUE_END}]/, '')
    end

    private

    # ── Entry point for processing a block of source ─────────────────────────

    def process_source(source, filename)
      @output    ||= +''
      # C standard: phase 2 (line splicing) before phase 3 (comment stripping).
      # Keep original lines so we can use them to detect continuation backslashes
      # that may have been inside block comments (and thus stripped away).
      orig_lines = source.split("\n", -1)
      stripped   = strip_comments(source)
      lines      = stripped.split("\n", -1)
      stripped   = nil
      i          = 0

      while i < lines.length
        raw      = lines[i]
        lines[i] = nil

        # Splice continuations. Use the original (pre-strip) line to detect a
        # trailing backslash that strip_comments may have removed (e.g. a `\`
        # inside a block comment like `/* foo \` still acts as a line
        # continuation per C phase 2, which runs before comment stripping).
        while (raw.end_with?('\\') || (orig_lines[i] || '').end_with?('\\')) &&
              i + 1 < lines.length
          raw = (raw.end_with?('\\') ? raw.chomp('\\') : raw) + lines[i + 1]
          i  += 1
        end

        stripped = raw.lstrip

        if stripped.start_with?('#')
          # Replace __FILE__ and __LINE__ in the directive itself
          directive_line = stripped[1..].lstrip
          i = handle_directive(directive_line, filename, i, lines)
        elsif active?
          # Join subsequent lines until open parentheses are balanced.
          # This handles function-like macro calls that span multiple lines.
          # When a directive line appears mid-join, emit the current
          # accumulation, reset raw to empty, and point i back at the
          # directive so the outer loop processes it normally.
          while paren_depth_outside_strings(raw) > 0 && i + 1 < lines.length
            next_stripped = lines[i + 1].lstrip
            if next_stripped.start_with?('#')
              # Emit what we have so far; the lexer treats the whole output
              # as one token stream, so an unbalanced partial line is fine.
              expanded = expand_macros(raw, filename, i + 1)
              @output  << expanded << "\n"
              raw = ''
              # Leave i pointing at the current line; the outer i+=1 below
              # will advance to the directive line, which the outer loop
              # will then handle normally on the next iteration.
              break
            else
              i  += 1
              raw = raw + "\n" + lines[i]
            end
          end

          expanded = expand_macros(raw, filename, i + 1)
          @output  << expanded << "\n"
          i += 1
        else
          @output << "\n" if @include_depth == 0
          i += 1
        end
      end
    end

    # Count the net open-paren depth of text, skipping string/char literals
    # and both // line comments and /* block comments */.
    def paren_depth_outside_strings(text)
      depth      = 0
      in_str     = false
      in_char    = false
      in_block   = false   # inside /* ... */
      escape     = false
      chars      = text.chars
      n          = chars.length
      k          = 0
      while k < n
        c = chars[k]

        if escape
          escape = false
          k += 1
          next
        end

        if in_block
          if c == '*' && chars[k + 1] == '/'
            in_block = false
            k += 2
          else
            k += 1
          end
          next
        end

        if in_str
          case c
          when '\\' then escape = true
          when '"'  then in_str = false
          end
          k += 1
          next
        end

        if in_char
          case c
          when '\\' then escape = true
          when "'"  then in_char = false
          end
          k += 1
          next
        end

        # Outside any literal or comment
        if c == '/' && chars[k + 1] == '*'
          in_block = true
          k += 2
          next
        elsif c == '/' && chars[k + 1] == '/'
          break   # rest of line is a // comment
        end

        case c
        when '"'  then in_str  = true
        when "'"  then in_char = true
        when '('  then depth  += 1
        when ')'  then depth  -= 1
        end
        k += 1
      end
      depth
    end

    # Strip C and C++ style comments from the source before directive
    # processing and macro expansion.  Block comments are replaced with a
    # single space (preserving any newlines inside, so line numbers stay
    # aligned).  Line comments are stripped to end of line.  String and
    # character literals are left untouched.
    def strip_comments(text)
      out      = +''
      in_str   = false
      in_char  = false
      in_block = false
      escape   = false
      i        = 0
      n        = text.length
      while i < n
        c  = text[i]
        c2 = text[i + 1]

        if escape
          out << c
          escape = false
          i += 1
          next
        end

        if in_block
          if c == '*' && c2 == '/'
            out << ' '
            i += 2
            in_block = false
          else
            out << c if c == "\n"
            i += 1
          end
          next
        end

        if in_str
          out << c
          if c == '\\'
            escape = true
          elsif c == '"'
            in_str = false
          end
          i += 1
          next
        end

        if in_char
          out << c
          if c == '\\'
            escape = true
          elsif c == "'"
            in_char = false
          end
          i += 1
          next
        end

        if c == '/' && c2 == '*'
          in_block = true
          out << ' '
          i += 2
          next
        elsif c == '/' && c2 == '/'
          # consume to end of line (do not consume the newline)
          i += 2
          i += 1 while i < n && text[i] != "\n"
          next
        end

        out << c
        case c
        when '"'  then in_str  = true
        when "'"  then in_char = true
        end
        i += 1
      end
      out
    end

    # Returns the new value of i after processing the directive.
    def handle_directive(directive, filename, i, lines)
      keyword, rest = directive.split(/\s+/, 2)
      keyword = keyword.to_s  # nil from empty directive → ''
      rest = (rest || '').strip

      case keyword
      when 'define'
        process_define(rest, filename, i + 1) if active?
      when 'undef'
        @macros.delete(rest.strip) if active?
      when 'include'
        process_include(rest, filename, i + 1) if active?
      when 'ifdef'
        name = rest.strip
        push_if(@macros.key?(name))
      when 'ifndef'
        name = rest.strip
        push_if(!@macros.key?(name))
      when 'if'
        push_if(eval_constant_expr(rest))
      when 'elif'
        handle_elif(eval_constant_expr(rest))
      when 'else'
        handle_else
      when 'endif'
        pop_if(filename, i + 1)
      when 'error'
        raise PreprocError.new(rest, SourceLocation.new(filename, i + 1, 1)) if active?
      when 'pragma'
        process_pragma(rest, filename) if active?
      when 'line'
        # #line directive – update filename/line tracking (simplified: ignore)
        nil
      when ''
        nil   # null directive
      else
        # Unknown directive – warn in active sections
        warn "#{filename}:#{i + 1}: warning: unknown directive '##{keyword}'" if active?
      end

      @output << "\n" if @include_depth == 0   # preserve line count for main file only
      i + 1
    end

    # ── #define ───────────────────────────────────────────────────────────────

    def process_define(rest, _filename, _lineno)
      if rest =~ /\A([a-zA-Z_]\w*)\(([^)]*)\)\s*(.*)\z/m
        # Function-like macro
        name   = Regexp.last_match(1)
        params = Regexp.last_match(2).split(',').map(&:strip)
        body   = Regexp.last_match(3)
        variadic = params.last == '...'
        params.pop if variadic
        @macros[name] = { kind: :function, params: params, variadic: variadic, body: body }
      elsif rest =~ /\A([a-zA-Z_]\w*)(?:\s+(.*))?\z/m
        # Object-like macro
        name = Regexp.last_match(1)
        body = (Regexp.last_match(2) || '').strip
        define_object_macro(name, body)
      end
    end

    def define_object_macro(name, body)
      @macros[name] = { kind: :object, body: body }
    end

    # ── #include ──────────────────────────────────────────────────────────────

    def process_include(rest, from_file, lineno)
      # If the argument is neither "..." nor <...>, macro-expand it first
      # (e.g. #include THREAD_IMPL_H where the macro expands to "thread_pthread.h")
      rest = expand_macros(rest.strip, from_file, lineno).strip unless rest.strip.start_with?('"', '<')

      path = resolve_include(rest, from_file)
      unless path
        raise PreprocError.new("cannot find include file: #{rest}",
                               SourceLocation.new(from_file, lineno, 1))
      end

      return if @once_files.include?(path)

      # Allow at most one level of intentional self-inclusion (X-macro pattern).
      # True infinite recursion is caught by the include guard mechanism or the depth cap.
      if @include_stack.count(path) >= 2
        raise PreprocError.new("recursive include: #{path}",
                               SourceLocation.new(from_file, lineno, 1))
      end

      content = File.binread(path).force_encoding('UTF-8')

      # Handle #pragma once at the top of the file
      if content.lstrip.start_with?('#pragma once') ||
         content.lines.any? { |l| l.strip == '#pragma once' }
        @once_files << path
      end

      @include_stack.push(path)
      @include_depth += 1
      saved_output = @output
      @output = +''
      process_source(content, path)
      included = @output
      @output = saved_output
      @output << included
      @include_stack.pop
      @include_depth -= 1
    end

    def resolve_include(spec, from_file)
      spec = spec.strip
      if spec.start_with?('"')
        # Local include: search relative to including file first
        name = spec[1...-1]
        local = File.join(File.dirname(from_file), name)
        return local if File.exist?(local)
      elsif spec.start_with?('<')
        name = spec[1...-1]
      else
        return nil
      end

      # Search include paths
      @include_paths.each do |dir|
        candidate = File.join(dir, name)
        return candidate if File.exist?(candidate)
      end

      # Search framework paths for <Framework/Header.h> style includes
      if name.include?('/')
        parts = name.split('/', 2)
        fw_name, header = parts[0], parts[1]
        @framework_paths.each do |fdir|
          candidate = File.join(fdir, "#{fw_name}.framework", 'Headers', header)
          return candidate if File.exist?(candidate)
        end
      end

      nil
    end

    # ── Conditional stack ─────────────────────────────────────────────────────

    def push_if(condition)
      @if_stack.push({ active: condition, seen_true: condition })
    end

    def handle_elif(condition)
      raise PreprocError.new('#elif without #if') if @if_stack.empty?
      top = @if_stack.last
      if top[:seen_true]
        top[:active] = false
      elsif condition
        top[:active]     = true
        top[:seen_true]  = true
      end
    end

    def handle_else
      raise PreprocError.new('#else without #if') if @if_stack.empty?
      top = @if_stack.last
      top[:active] = !top[:seen_true]
    end

    def pop_if(_filename, _lineno)
      raise PreprocError.new('#endif without #if') if @if_stack.empty?
      @if_stack.pop
    end

    def active?
      @if_stack.all? { |frame| frame[:active] }
    end

    # ── #pragma ───────────────────────────────────────────────────────────────

    def process_pragma(rest, filename)
      s = rest.strip
      if s == 'once'
        @once_files << filename
      elsif s =~ /\Apack\s*\((.*)\)\z/i
        emit_pragma_pack($1.strip)
      end
    end

    def emit_pragma_pack(args_str)
      parts = args_str.split(',').map(&:strip)
      case parts[0]
      when 'push'
        @output << '__occ_pragma_pack__(push);'
        @output << "__occ_pragma_pack__(#{parts[1]});" if parts[1]
      when 'pop'
        @output << '__occ_pragma_pack__(pop);'
      when ''
        @output << '__occ_pragma_pack__(0);'
      else
        @output << "__occ_pragma_pack__(#{parts[0]});"
      end
    end

    # ── Macro expansion ───────────────────────────────────────────────────────
    #
    # Implements object-like and basic function-like macro expansion, plus
    # the # stringification and ## token-paste operators.

    def expand_macros(text, filename, lineno)
      # Iterative expansion (max 32 passes to prevent infinite loops).
      # __FILE__ and __LINE__ are handled inside expand_pass so they are
      # respected only outside string/char literals.
      32.times do
        expanded = expand_pass(text, file: filename, line: lineno)
        break if expanded == text
        text = expanded
      end
      text
    end

    # Sentinel characters used to "freeze" already-expanded argument tokens so
    # they are not re-expanded during the macro body rescan.  These are C0
    # control characters that never appear in real C source.
    FROZEN_START = "\x01"
    FROZEN_END   = "\x02"

    # "Blue paint" sentinels: mark tokens that were suppressed due to the C
    # §6.10.3.4 blue-paint rule (self-referential macros).  Unlike FROZEN
    # markers (which are stripped by expand_pass after one rescan), BLUE
    # markers are preserved across all passes of the outer expand_macros loop
    # and are only removed at the very end of processing.
    BLUE_START = "\x03"
    BLUE_END   = "\x04"

    # expand_pass performs one (deep) macro expansion pass over `text`.
    # `expanding` is the Set of macro names currently being expanded; any name
    # in this set is treated as a literal token (C §6.10.3.4 "blue paint").
    def expand_pass(text, expanding: Set.new, file: nil, line: nil)
      result  = +''
      i       = 0
      in_str  = false
      in_char = false
      escape  = false

      while i < text.length
        ch = text[i]

        # Handle escape sequences inside string/char literals.
        if escape
          result << ch
          escape = false
          i += 1
          next
        end

        if in_str
          result << ch
          if ch == '\\'
            escape = true
          elsif ch == '"'
            in_str = false
          end
          i += 1
          next
        end

        if in_char
          result << ch
          if ch == '\\'
            escape = true
          elsif ch == "'"
            in_char = false
          end
          i += 1
          next
        end

        # Enter string or char literals without expanding inside them.
        if ch == '"'
          result << ch
          in_str = true
          i += 1
          next
        end

        if ch == "'"
          result << ch
          in_char = true
          i += 1
          next
        end

        # Frozen token: copy the content literally without expansion.
        if ch == FROZEN_START
          j = text.index(FROZEN_END, i + 1) || (text.length - 1)
          result << text[i + 1...j]
          i = j + 1
          next
        end

        # Blue-painted token: copy the content literally AND keep the markers
        # so the outer expand_macros loop doesn't re-expand it.
        if ch == BLUE_START
          j = text.index(BLUE_END, i + 1) || (text.length - 1)
          result << BLUE_START << text[i + 1...j] << BLUE_END
          i = j + 1
          next
        end

        # Try to match an identifier at position i
        if ch =~ /[a-zA-Z_]/
          j = i
          j += 1 while j < text.length && text[j] =~ /\w/
          name = text[i...j]

          # __FILE__ and __LINE__ are built-in position macros; handle here so
          # they are never expanded inside string or char literals (the in_str/
          # in_char guards above already prevent us reaching this branch while
          # inside a literal).
          if name == '__FILE__' && file
            result << %("#{file}")
            i = j
            next
          elsif name == '__LINE__' && line
            result << line.to_s
            i = j
            next
          end

          if (macro = @macros[name]) && !expanding.include?(name)
            if macro[:kind] == :function && text[j..].lstrip.start_with?('(')
              # Consume argument list
              k     = text.index('(', j)
              args, after = consume_arguments(text, k + 1)
              # __attribute__((constructor)) → __occ_constructor so codegen can
              # emit the function address in __mod_init_func.
              if (name == '__attribute__' || name == '__attribute') &&
                 args.first.to_s.strip.match?(/^\(\s*constructor\s*\)$/)
                result << '__occ_constructor'
              elsif (name == '__attribute__' || name == '__attribute') &&
                    args.first.to_s.strip.match?(/^\(\s*packed\b.*\)$/)
                result << '__occ_packed'
              else
                replacement = expand_function_macro(macro, args, name, expanding: expanding)
                result << replacement
              end
              i = after
            elsif macro[:kind] == :object
              # Recursively expand body with this macro name disabled so
              # self-referential macros (A → ... → A) produce a literal A.
              result << expand_pass(macro[:body], expanding: expanding | Set[name])
              i = j
            else
              result << name
              i = j
            end
          else
            # Not a known macro, or it's in the expanding set (blue-painted).
            # Blue-paint suppressed macro occurrences so the outer
            # expand_macros loop doesn't re-expand them (C §6.10.3.4).
            if expanding.include?(name) && @macros.key?(name)
              result << BLUE_START << name << BLUE_END
            else
              result << name
            end
            i = j
          end
        else
          result << ch
          i += 1
        end
      end
      result
    end

    # Consume comma-separated macro arguments, respecting nested parens and
    # string/char literals (so a comma inside "," is not treated as a separator).
    # Returns [args_array, index_after_closing_paren].
    def consume_arguments(text, start)
      args    = []
      depth   = 1
      current = +''
      i       = start
      in_str  = false
      in_char = false
      escape  = false

      while i < text.length
        ch = text[i]

        if escape
          escape = false
          current << ch
          i += 1
          next
        end

        if in_str
          current << ch
          if ch == '\\'
            escape = true
          elsif ch == '"'
            in_str = false
          end
          i += 1
          next
        end

        if in_char
          current << ch
          if ch == '\\'
            escape = true
          elsif ch == "'"
            in_char = false
          end
          i += 1
          next
        end

        case ch
        when '('
          depth += 1
          current << ch
        when ')'
          depth -= 1
          if depth.zero?
            args << current.strip
            return [args, i + 1]
          else
            current << ch
          end
        when ','
          if depth == 1
            args << current.strip
            current = +''
          else
            current << ch
          end
        when '"'
          in_str = true
          current << ch
        when "'"
          in_char = true
          current << ch
        else
          current << ch
        end
        i += 1
      end

      [args, i]
    end

    # Like String#gsub but skips content inside string and char literals.
    # The block receives the full matched string as its argument (not via $1).
    def gsub_outside_strings(text, regex, &block)
      result  = +''
      i       = 0
      escape  = false
      in_str  = false
      in_char = false
      chunk   = +''

      while i < text.length
        ch = text[i]
        if escape
          (in_str || in_char ? (result << ch) : (chunk << ch))
          escape = false; i += 1; next
        end
        if in_str
          if ch == '\\'
            result << ch; escape = true
          elsif ch == '"'
            result << ch; in_str = false
          else
            result << ch
          end
          i += 1; next
        end
        if in_char
          if ch == '\\'
            result << ch; escape = true
          elsif ch == "'"
            result << ch; in_char = false
          else
            result << ch
          end
          i += 1; next
        end
        if ch == '"'
          result << chunk.gsub(regex) { |m| block.call(m) }
          chunk = +''
          result << ch; in_str = true; i += 1; next
        end
        if ch == "'"
          result << chunk.gsub(regex) { |m| block.call(m) }
          chunk = +''
          result << ch; in_char = true; i += 1; next
        end
        chunk << ch
        i += 1
      end
      result << chunk.gsub(regex) { |m| block.call(m) }
      result
    end

    def expand_function_macro(macro, args, name, expanding: Set.new)
      body = macro[:body].dup
      # raw_param_map is used for # stringification and ## token paste (C standard:
      # these operators act on the unexpanded argument text).
      raw_param_map = macro[:params].each_with_index.to_h { |p, i| [p, args[i] || ''] }

      # ## token paste: substitute both sides before concatenating.
      # Loop because a##b##c requires two passes (a##b → ab, then ab##c → abc).
      loop do
        prev = body.dup
        body.gsub!(/([a-zA-Z_]\w*|[0-9]+)\s*##\s*([a-zA-Z_]\w*|[0-9]+)/) do
          (raw_param_map[$1] || $1) + (raw_param_map[$2] || $2)
        end
        break if body == prev
      end
      # Remove any remaining ## (e.g., empty-argument paste or ##__VA_ARGS__).
      body.gsub!(/\s*##\s*/, '')

      # # stringification (must run before parameter substitution)
      macro[:params].each_with_index do |param, idx|
        arg = args[idx] || ''
        body.gsub!(/\#\s*#{Regexp.escape(param)}/) { arg.inspect }
      end

      # Parameter substitution: expand each arg (with the current disabled set,
      # NOT including `name`), then wrap in frozen markers so the substituted
      # tokens survive the body rescan without being re-expanded.
      unless macro[:params].empty?
        frozen_param_map = raw_param_map.transform_values { |v|
          expanded = expand_pass(v, expanding: expanding)
          "#{FROZEN_START}#{expanded}#{FROZEN_END}"
        }
        param_regex = Regexp.new('\\b(' + macro[:params].map { |p| Regexp.escape(p) }.join('|') + ')\\b')
        body = gsub_outside_strings(body, param_regex) { |m| frozen_param_map[m] || m }
      end

      # Variadic __VA_ARGS__: expand and freeze
      if macro[:variadic]
        va_args = args[macro[:params].length..].map { |a|
          expanded = expand_pass(a, expanding: expanding)
          "#{FROZEN_START}#{expanded}#{FROZEN_END}"
        }.join(', ')
        body.gsub!('__VA_ARGS__') { va_args }
      end

      # Rescan the substituted body with this macro name disabled, so any
      # occurrence of `name` in the result is treated as a literal identifier.
      # Frozen tokens from the arg substitution above are copied without
      # expansion, implementing C §6.10.3.4 "blue paint" for arguments.
      expand_pass(body, expanding: expanding | Set[name])
    end

    # ── Constant expression evaluator for #if / #elif ─────────────────────────
    #
    # Supports: integer literals, defined(X), !, &&, ||,
    # ==, !=, <, >, <=, >=, +, -, *, /, unary minus.

    def eval_constant_expr(expr)
      expr = expr.strip
      # Step 0: resolve __has_include() — only returns 1 for files in OCC's own include dir
      # (avoids pulling in huge Apple SDK chains for conditionally-included system headers)
      occ_dir = File.expand_path('../include', __FILE__)
      expr = expr.gsub(/__has_include\s*\(\s*([<"][^>"]*[>"])\s*\)/) do
        spec = Regexp.last_match(1)
        name = spec[1...-1]
        occ_path = File.join(occ_dir, name)
        File.exist?(occ_path) ? '1' : '0'
      end
      # Step 1: resolve defined() BEFORE any macro expansion
      expr = expr.gsub(/defined\s*\(\s*([a-zA-Z_]\w*)\s*\)/) do
        @macros.key?(Regexp.last_match(1)) ? '1' : '0'
      end
      expr = expr.gsub(/defined\s+([a-zA-Z_]\w*)/) do
        @macros.key?(Regexp.last_match(1)) ? '1' : '0'
      end
      # Step 1b: replace character literals with their ASCII integer values
      # Handles simple char literals: 'x' → ASCII, '\n' → 10, '\t' → 9, '\\' → 92, etc.
      expr = expr.gsub(/'(\\?.)'/) do
        ch = Regexp.last_match(1)
        if ch.start_with?('\\')
          case ch[1]
          when 'n'  then 10
          when 't'  then 9
          when 'r'  then 13
          when '0'  then 0
          when '\\' then 92
          when '\'' then 39
          when '"'  then 34
          else ch[1].ord
          end
        else
          ch.ord
        end.to_s
      end
      # Step 2: expand remaining macros
      expr = expand_macros(expr, '<if>', 0)
      # Step 3: replace any remaining unknown identifiers with 0
      expr = expr.gsub(/\b[a-zA-Z_]\w*\b/, '0')

      begin
        result = eval_expr(expr) # rubocop:disable Security/Eval — isolated arithmetic
        !result.zero?
      rescue StandardError
        false
      end
    end

    # Safe integer arithmetic evaluator (no Kernel.eval).
    def eval_expr(expr)
      tokens = expr.scan(/&&|\|\||==|!=|<=|>=|<<|>>|\d+|[()!&|<>=+\-*\/]/)
      parser = ConstExprParser.new(tokens)
      parser.parse
    end

    # ── Minimal constant-expression parser ───────────────────────────────────

    class ConstExprParser
      PREC = { '||' => 1, '&&' => 2, '==' => 3, '!=' => 3,
               '<' => 4, '>' => 4, '<=' => 4, '>=' => 4,
               '<<' => 5, '>>' => 5,
               '+' => 6, '-' => 6, '*' => 7, '/' => 7 }.freeze

      def initialize(tokens)
        @tokens = tokens
        @pos    = 0
      end

      def parse
        result = parse_expr(0)
        result
      end

      private

      def cur    = @tokens[@pos]
      def advance = @tokens[@pos].tap { @pos += 1 }

      def parse_expr(min_prec)
        left = parse_unary

        loop do
          op = cur
          break unless op && PREC.key?(op) && PREC[op] >= min_prec
          advance
          right = parse_expr(PREC[op] + 1)
          left = apply_binop(op, left, right)
        end

        left
      end

      def parse_unary
        if cur == '!'
          advance
          val = parse_unary
          return val.zero? ? 1 : 0
        end
        if cur == '-'
          advance
          return -parse_unary
        end
        parse_primary
      end

      def parse_primary
        if cur == '('
          advance
          val = parse_expr(0)
          advance if cur == ')'
          return val
        end
        advance.to_i
      end

      def apply_binop(op, l, r)
        case op
        when '||'  then (l != 0 || r != 0) ? 1 : 0
        when '&&'  then (l != 0 && r != 0) ? 1 : 0
        when '=='  then l == r ? 1 : 0
        when '!='  then l != r ? 1 : 0
        when '<'   then l <  r ? 1 : 0
        when '>'   then l >  r ? 1 : 0
        when '<='  then l <= r ? 1 : 0
        when '>='  then l >= r ? 1 : 0
        when '<<'  then l << r
        when '>>'  then l >> r
        when '+'   then l + r
        when '-'   then l - r
        when '*'   then l * r
        when '/'   then r.zero? ? 0 : l / r
        else 0
        end
      end
    end
  end
end
