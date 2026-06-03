# occ

A C compiler written from scratch in Ruby, built in homage to [kefir C](https://git.sr.ht/~jprotopopov/kefir).

## About

occ is a complete C compiler pipeline — preprocessor, lexer, parser, semantic analyzer, IR builder, and code generator — implemented in pure Ruby. It targets ARM64 (Apple Silicon macOS) and AMD64 (Linux and macOS) natively, auto-detecting the host architecture at runtime.

The project is a learning exercise in compiler construction. It is not production-ready but successfully compiles and runs real C programs including loops, conditionals, multi-function programs, and printf.

**Status:** Phase 8 complete. 263 tests, 0 failures.

## Pipeline

```
Source (.c)
  → Preprocessor  (#include, #define, conditionals)
  → Lexer         (tokens with source locations)
  → Parser        (AST — recursive descent, C11)
  → Semantic      (type checking, symbol table)
  → IR Builder    (three-address code, basic blocks)
  → Codegen       (ARM64 or AMD64 assembly)
  → Assembler     (via system `as`)
  → Linker        (via `clang`)
  → Executable
```

## Requirements

- Ruby 3.4+
- `clang` and `as` (for assembling and linking — standard on macOS, available via LLVM on Linux)

## Installation

```sh
git clone <repo>
cd occ
bundle install
```

## Usage

### Compile to an executable

```sh
bundle exec ruby bin/occ hello.c -o hello
./hello
```

### Compile to object file only

```sh
bundle exec ruby bin/occ -c hello.c -o hello.o
```

### Print assembly to stdout (no `-o` flag)

```sh
bundle exec ruby bin/occ hello.c
```

### With include paths and defines

```sh
bundle exec ruby bin/occ -I./include -DDEBUG=1 program.c -o program
```

## Example

```c
// hello.c
extern int printf(const char *fmt, ...);

int main(void) {
    printf("Hello, world!\n");
    return 0;
}
```

```sh
bundle exec ruby bin/occ hello.c -o hello && ./hello
# Hello, world!
```

```c
// fib.c
extern int printf(const char *fmt, ...);

int fib(int n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    for (int i = 0; i < 10; i++) {
        printf("%d\n", fib(i));
    }
    return 0;
}
```

```sh
bundle exec ruby bin/occ fib.c -o fib && ./fib
# 0
# 1
# 1
# 2
# ...
```

## Running the Tests

All phases:
```sh
bundle exec rspec
```

A specific phase:
```sh
bundle exec rspec spec/phase8/
```

Via Rake:
```sh
bundle exec rake spec           # all phases
bundle exec rake spec:phase8    # one phase
```

## Project Structure

```
bin/occ                    # CLI entry point
lib/occ/
  driver.rb                # top-level pipeline orchestration
  preprocessor.rb          # #include / #define / conditionals
  lexer.rb                 # tokenizer
  parser.rb                # recursive-descent C11 parser
  ast.rb                   # AST node definitions
  types.rb                 # C type hierarchy
  symbol_table.rb          # scoped symbol table
  semantic.rb              # type checking and analysis
  ir.rb                    # IR builder and data structures
  codegen/
    base.rb                # shared codegen helpers
    amd64.rb               # AMD64 System-V ABI backend
    arm64.rb               # ARM64 Apple ABI backend
spec/
  phase1/ … phase8/        # per-phase RSpec suites
```

## Documentation

- [PLAN.md](PLAN.md) — phased development plan with current status
- [RESOURCES.md](RESOURCES.md) — specifications, ABI docs, and references
- [NOTABLE_FINDINGS.md](NOTABLE_FINDINGS.md) — non-obvious design decisions and bugs encountered

## License

TBD
