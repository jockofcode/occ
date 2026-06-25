# frozen_string_literal: true

require 'tmpdir'

module OCC
  class Driver
    def self.run(args)
      options = parse_options(args)

      if options[:files].empty?
        warn 'occ: error: no input files'
        exit 1
      end

      options[:files].each do |file|
        unless File.exist?(file)
          warn "occ: error: #{file}: No such file or directory"
          exit 1
        end
      end

      # Multiple sources + link: compile each .c to a temp .o, pass .o/.a files directly.
      if !options[:compile_only] && options[:output] && options[:files].length > 1
        Dir.mktmpdir do |tmp|
          obj_paths = options[:files].map.with_index do |file, i|
            if file.end_with?('.o', '.a')
              file
            else
              source   = File.binread(file).force_encoding('UTF-8')
              asm      = compile_source(source, file, options)
              asm_path = File.join(tmp, "out#{i}.s")
              obj_path = File.join(tmp, "out#{i}.o")
              File.write(asm_path, asm)
              assemble_to_obj(asm_path, obj_path, options[:target])
              obj_path
            end
          end
          link(obj_paths, options[:output], options[:target])
        end
        return
      end

      options[:files].each { |file| compile_file(file, options) }
    end

    # Compile a single source file according to options.
    def self.compile_file(path, options)
      source = File.binread(path).force_encoding('UTF-8')
      asm    = compile_source(source, path, options)

      if options[:compile_only]
        # -c: produce .o file
        obj_path = options[:output] || path.sub(/\.c\z/, '.o')
        assemble(asm, obj_path, options[:target])
      elsif options[:output]
        # Produce executable
        Dir.mktmpdir do |tmp|
          asm_path = File.join(tmp, 'out.s')
          obj_path = File.join(tmp, 'out.o')
          File.write(asm_path, asm)
          assemble_to_obj(asm_path, obj_path, options[:target])
          link(obj_path, options[:output], options[:target])
        end
      else
        # No -o: just print the assembly (useful for debugging)
        print asm
      end
    end

    # Full compilation pipeline: source text → assembly text
    def self.compile_source(source, filename, options = {})
      require_relative 'preprocessor'
      require_relative 'token'
      require_relative 'lexer'
      require_relative 'ast'
      require_relative 'parser'
      require_relative 'types'
      require_relative 'symbol_table'
      require_relative 'semantic'
      require_relative 'ir'
      require_relative 'codegen/base'
      require_relative 'codegen/amd64'
      require_relative 'codegen/arm64'

      target        = options[:target] || detect_target
      occ_include   = File.join(File.dirname(__FILE__), 'include')
      include_paths = [occ_include] + (options[:include_paths] || [])
      defines       = options[:defines] || []

      # Phase 3: Preprocess
      pp     = Preprocessor.new(source, filename,
                                include_paths: include_paths,
                                defines: defines,
                                target: target)
      source = pp.process

      # Phase 2: Lex
      tokens = Lexer.new(source, filename).tokenize

      # Phase 4: Parse
      ast = Parser.new(tokens).parse

      # Phase 5: Semantic analysis
      sa = Semantic.new
      sa.analyze(ast)
      sa.errors.each { |e| warn "occ: #{e.message}" }

      # Phase 6: IR
      ir_mod = IR::Builder.new.build(ast)

      # Phase 7: Code generation
      gen = case target
            when :arm64_macos
              Codegen::ARM64.new(ir_mod, target: target)
            else
              Codegen::AMD64.new(ir_mod, target: target)
            end

      gen.generate
    end

    def self.assemble(asm_text, obj_path, target)
      Dir.mktmpdir do |tmp|
        asm_path = File.join(tmp, 'in.s')
        File.write(asm_path, asm_text)
        assemble_to_obj(asm_path, obj_path, target)
      end
    end

    def self.assemble_to_obj(asm_path, obj_path, target)
      arch_flag = target == :arm64_macos ? '-arch arm64' : ''
      cmd = "as #{arch_flag} -o #{obj_path} #{asm_path} 2>&1"
      out = `#{cmd}`
      unless $?.success?
        warn "occ: assembler error:\n#{out}"
        exit 1
      end
    end

    def self.link(obj_paths, exe_path, target)
      objs = Array(obj_paths).join(' ')
      case target
      when :arm64_macos, :amd64_macos
        cmd = "clang -o #{exe_path} #{objs} 2>&1"
      else
        cmd = "cc -o #{exe_path} #{objs} 2>&1"
      end
      out = `#{cmd}`
      unless $?.success?
        warn "occ: linker error:\n#{out}"
        exit 1
      end
    end

    def self.parse_options(args)
      options = {
        files:         [],
        output:        nil,
        compile_only:  false,
        include_paths: [],
        defines:       [],
        target:        detect_target
      }

      i = 0
      while i < args.length
        case args[i]
        when '-o'
          options[:output] = args[i + 1]
          i += 2
        when '-c'
          options[:compile_only] = true
          i += 1
        when /\A-I(.+)/
          options[:include_paths] << Regexp.last_match(1)
          i += 1
        when '-I'
          options[:include_paths] << args[i + 1]
          i += 2
        when /\A-D(.+)/
          options[:defines] << Regexp.last_match(1)
          i += 1
        when '-D'
          options[:defines] << args[i + 1]
          i += 2
        else
          options[:files] << args[i]
          i += 1
        end
      end

      options
    end

    def self.detect_target
      arch = `uname -m`.strip
      os   = `uname -s`.strip
      case [arch, os]
      when ['arm64',  'Darwin'] then :arm64_macos
      when ['x86_64', 'Darwin'] then :amd64_macos
      when ['x86_64', 'Linux']  then :amd64_linux
      else :amd64_linux
      end
    end
    private_class_method :detect_target
  end
end
