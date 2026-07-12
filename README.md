# occ

A C compiler written from scratch in Ruby, built in homage to [kefir C](https://git.sr.ht/~jprotopopov/kefir).

## About

occ is a complete C compiler pipeline — preprocessor, lexer, parser, semantic analyzer, IR builder, and code generator — implemented in pure Ruby. It targets ARM64 (Apple Silicon macOS) and AMD64 (Linux and macOS) natively, auto-detecting the host architecture at runtime.

The project is a learning exercise in compiler construction. It is not production-ready but successfully compiles and runs real-world C libraries including Lua 5.5, zlib, SQLite, and more.

**Status:** Phases 1–13 are broadly complete. Current development is focused on Phase 11 Tier 4: CRuby 3.4 `miniruby` bring-up on macOS/ARM64. See [CURRENT_STATUS.md](CURRENT_STATUS.md) for the latest verified tests and active blocker.

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

### Link multiple source files

```sh
bundle exec ruby bin/occ a.c b.c c.c -o program
```

## Example

```c
// hello.c
#include <stdio.h>

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
#include <stdio.h>

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
# 0 1 1 2 3 5 8 13 21 34
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

Third-party compilation tests (requires network, ~5–15 min first run to clone repos):
```sh
THIRDPARTY=1 bundle exec rspec spec/phase11/thirdparty_spec.rb
```

## Third-Party Libraries

occ compiles and passes the test suites of the following real-world C projects:

| Library | Description | Tests |
|---|---|---|
| [jsmn](https://github.com/zserge/jsmn) | JSON tokenizer (~300 lines) | 16/16 |
| [tinyexpr](https://github.com/codeplea/tinyexpr) | Math expression evaluator | 4930 |
| [tiny-regex-c](https://github.com/kokke/tiny-regex-c) | Regex engine | 76 |
| [munit](https://github.com/nemequ/munit) | Unit test micro-framework | 11 |
| [parson](https://github.com/kgabis/parson) | JSON library | 349 |
| [smaz](https://github.com/antirez/smaz) | Short-string compression | all |
| [sds](https://github.com/antirez/sds) | Simple dynamic strings | 46 |
| [genann](https://github.com/codeplea/genann) | Minimal neural network | 1077 |
| [utf8.h](https://github.com/sheredom/utf8.h) | Header-only UTF-8 library | 156 |
| [linenoise](https://github.com/antirez/linenoise) | Readline replacement | all |
| [Lua 5.5](https://lua.org) | Full scripting language interpreter | all |
| [zlib 1.3.2](https://github.com/madler/zlib) | Compression library | all |
| [SQLite 3.47.2](https://sqlite.org) | Embedded SQL database (~250K lines) | CRUD + txns |

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
  include/                 # bundled system headers
spec/
  phase1/ … phase11/       # per-phase RSpec suites
  support/
    thirdparty_helper.rb   # git_clone, occ_compile, shell helpers
tmp/
  thirdparty_cache/        # cached third-party repos (gitignored)
```

## Documentation

- [PLAN.md](PLAN.md) — phased development plan with current status
- [RESOURCES.md](RESOURCES.md) — specifications, ABI docs, and references
- [NOTABLE_FINDINGS.md](NOTABLE_FINDINGS.md) — non-obvious design decisions and bugs encountered
- [CURRENT_STATUS.md](CURRENT_STATUS.md) — detailed current state and recent fixes

## License

TBD
