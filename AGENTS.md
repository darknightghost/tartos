# tartos

## General Rules

- All documentation and comments MUST be written in **English**.
- Indentation and formatting follow the project style tool `/scripts/autostyle`,
  with per-language configuration files checked in at the repository root:
  - C/C++: `.clang-format` (clang-format, 4-space indent, no tabs, 80-column
    limit, Allman function braces, aligned consecutive
    declarations/assignments/macros/comments). Static analysis uses
    `.clang-tidy` (naming checks enforce the Rust conventions below).
  - Python 3: `.style.yapf` (yapf, `based_on_style = pep8`, PEP 8 compatible).
  - Rust: `rustfmt.toml` (rustfmt, 80-column / 4-space to match C/C++).
  - Assembly: 4-space indentation, consistent with C/C++.
- After creating or modifying any source file, run `/scripts/autostyle <path>` on it.
- Bulk formatting: `tools/format-all.sh` formats everything under `dsl/`,
  `kernel/`, and `lib/`.
- Git hook: `tools/git-hooks/pre-commit` (activated via
  `git config core.hooksPath tools/git-hooks`) formats staged files under
  `dsl/`, `kernel/`, `lib/` and re-stages them automatically.

## Toolchain Requirements

Development targets the following language/tool versions:

- Python **3.14** (DSL scripts).
- C++ **26** (compile with `-std=c++26`; host g++ and `arm-none-eabi-g++`
  16.2.x both support it).
- Rust **1.99.1** (edition 2024).

## Naming Conventions

Symbol naming for C++, assembly, and Rust follows the Rust conventions:

| Kind                     | Style                    | Example              |
| ------------------------ | ------------------------ | -------------------- |
| Functions / methods      | `snake_case`             | `packet_send`        |
| Variables / parameters   | `snake_case`             | `queue_len`          |
| Types (struct/enum/trait)| `UpperCamelCase` (PascalCase) | `DriverDescriptor` |
| Enum / struct variants   | `UpperCamelCase`         | `Ready`              |
| Constants / statics      | `SCREAMING_SNAKE_CASE`   | `MAX_RETRY_COUNT`    |
| Traits                   | `UpperCamelCase` (+`able`/`ible`) | `Sendable`     |
| Crates / modules         | `snake_case`, no underscores at start/end | `drv_ipc` |
| Files / labels           | `snake_case` matching module/function purpose | `drv_ipc.c` |

Avoid abbreviations unless they are established domain terms.

C++ declaration style:

- Refer to types by their `UpperCamelCase` name only — never carry C-style tag
  prefixes (`struct tx_queue *`); pass objects as references (`TxQueue &`),
  pointers only when nullability or ownership requires it.
- Use fixed-width integer typedefs for interfaces: unsigned `U8`, `U16`,
  `U32`, `U64`; signed `S8`, `S16`, `S32`, `S64`; and `SizeType` for sizes.

## Include Style (C/C++)

- Quoted includes (`#include "x.h"`) are FORBIDDEN. Always use the angle-bracket
  form `#include <x.h>`.
- Never reference a file by a path relative to the current file. All includes
  are resolved from the configured include directories, so the path written
  must start at the include root.
- Includes are grouped by category, groups separated by one blank line, in the
  following order:
  1. Language/toolchain-provided files (C++ standard library, compiler
     intrinsics/runtime).
  2. System (OS/libc) headers.
  3. Third-party libraries — one group per library.
  4. Other modules of this project — one group per module.
  5. Files of the current module.
  6. If the current file is a `.cpp`/`.cc`, its corresponding header goes
     last, in its own group.
- If a group depends on another group, the depended-upon group MUST be placed
  above the dependent one.
- Within a group, include order is normalized alphabetically by
  `clang-format` (`SortIncludes` sorts inside each contiguous block; blocks are
  kept, not reordered, thanks to `IncludeBlocks: Preserve`). The example below
  is illustrative; the on-disk result after formatting is sorted per group.

Example — current file `c/c.cpp`:

```cpp
#include <cstdio>
#include <chrono>

#include <unistd.h>
#include <epoll.h>

#include <zlib.h>

#include <QtCore/QObject>

#include <a/a.h>
#include <a/ac.h>

#include <b/bb.h>

#include <c/a.h>
#include <c/b.h>

#include <c.c.h>
```

Groups in the example: (1) C++ standard library, (2) POSIX/system,
(3) third-party zlib and Qt, (4) other project modules `a`/`b`,
(5) current module `c`, (6) header of the current file `c.cpp`.

## Comment / Documentation Style

### C++ and Assembly — Doxygen

Use Doxygen comment blocks (`/** ... */` for declarations; `;` Doxygen-aware
comments in assembly where supported).

- Every public/internal function gets a full Doxygen block:
  - `@brief` states what the function does.
  - `@param` is written WITHOUT a direction tag only when every parameter is
    input-only. If any parameter is an output or in/out, direction tags are
    MANDATORY: `@param[out]` for outputs, `@param[in,out]` for in/out (and
    `@param[in]` for inputs in that mixed case).
  - `@return` documents the return value, including error codes.
  - `@note` MUST be used for ANY requirement placed on the caller:
    thread-safety, call-order constraints, locking requirements, pointer
    lifetime, allocation ownership, etc.
- Units MUST be stated in comments when the type does not encode them,
  e.g. `@param length Length (m)`. Time, byte size, buffer capacity and counts
  of physical units all need the unit or meaning of the count.
- Comment fields MUST be aligned to tab stops (aligned `@param` names,
  descriptions of the same field start at the same column across the block).
- Blank comment lines MUST separate blocks of different tag kinds (e.g. after
  `@brief`, after `@note`, after the last `@param`, before `@return`); never
  mix tag kinds in one contiguous block without a blank ` * ` line between.
- When declaration and implementation are separated:
  - The **declaration** (header) carries the **full** Doxygen function comment.
  - The **implementation** keeps only `@brief` in its Doxygen block.
- In long function implementations, interleave explanatory comments that help
  the reader understand non-obvious logic.

Example:

```cpp
/**
 * @brief   Enqueue one packet for transmission on the given queue.
 *
 * @note    NOT thread-safe: caller must hold the queue lock.
 *
 * @param   queue      Transmission queue to use.
 * @param   packet     Packet to enqueue; ownership transfers to the library.
 * @param   length     Payload size (B).
 *
 * @return  S32 status: 0 on success, negative errno on failure.
 */
S32 packet_enqueue(TxQueue &queue, Packet &packet, SizeType length);
```

### Rust — rustdoc

- Use `///` doc comments for public items (`pub fn`, `pub struct`, `pub trait`,
  `pub enum`), module-level `//!` docs at the top of each crate file.
- First line is a single-sentence summary; follow with a blank comment line for
  details.
- Document parameters/return semantics in prose or `# Arguments` / `# Returns` /
  `# Errors` sections; note caller obligations (thread-safety, `unsafe`
  preconditions) explicitly, using `# Safety` for `unsafe fn` preconditions.
- Units follow the same rule as C++: state them when the type does not encode them.

### Python 3 — pydoc

- Use double-quoted docstrings (`"""..."""`) on every public module, class, and
  function.
- First line is a concise summary; follow with argument/return descriptions
  (Google-style `Args:` / `Returns:` recommended and used consistently).
- State caller requirements (thread-safety, required context, ordering)
  explicitly.
- Units follow the same rule as C++: state them in the argument description.

## Repository Layout

| Directory | Purpose                                                              | License  |
| --------- | -------------------------------------------------------------------- | -------- |
| `kernel/` | Kernel sources                                                       | GPLv3    |
| `lib/`    | Userspace (application-facing) interface library                     | LGPLv3   |
| `doc/`    | Documentation sources                                                | —        |
| `dsl/`    | Python 3 DSL that compiles the driver-IPC interface                  | GPLv3    |
| `tools/`  | Repository maintenance scripts and git hooks (not product code)      | —        |

Every new source file MUST carry the correct SPDX header for its directory:

- `kernel/`, `dsl/`: `SPDX-License-Identifier: GPL-3.0-only`
- `lib/`: `SPDX-License-Identifier: LGPL-3.0-only`

## Build and Output Layout

Intermediate build artifacts and generated files are organized per
ISA / architecture / platform:

```text
build/<isa>/<arch>/<platform>/            # intermediate files (objects, generated sources)
output/<isa>/<arch>/<platform>/kernel/    # generated kernel files
output/<isa>/<arch>/<platform>/include/   # application-layer headers
output/<isa>/<arch>/<platform>/lib/       # application-layer runtime libraries
output/<isa>/<arch>/<platform>/doc/       # compiled developer documentation
```

- `<isa>` / `<arch>` / `<platform>` segments MUST stay in this order; use the
  same triple consistently across `build/` and `output/` for a given
  configuration.
- Nothing under `build/` or `output/` is ever committed to VCS (both trees are
  gitignored).
- Headers exported for userspace belong in `output/.../include/`; runtime
  libraries produced from `lib/` belong in `output/.../lib/`.
