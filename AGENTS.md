# Agent guidance for msort

These instructions apply to the entire repository, regardless of the agent or editor used.

## Zig version and APIs

- Target Zig **0.17.1**, as declared in `build.zig.zon`. Verify with `zig version`.
- Check the installed Zig 0.17 standard-library source or official documentation before
  introducing unfamiliar APIs; do not copy examples for older Zig releases without checking them.
- Use `std.Io` for I/O and pass the `io` context explicitly. In the executable, obtain the
  allocator and I/O context from `std.process.Init`; in tests, use `std.testing.io`.
- Pass explicit allocators to unmanaged containers, such as `std.ArrayList(T)`, and their
  allocating operations and cleanup methods. Use `.empty` for an empty list.
- For struct reflection, use `@typeInfo(T).@"struct".field_names` and `.field_types`
  rather than the deprecated `std.meta.fields`. Use `@Int(signedness, bits)` for integer types.
- In build scripts, forward `zig build run -- ...` arguments with `run_cmd.addPassthruArgs()`.

## Resource management and structure

- Pair successful allocations with `defer` for cleanup and `errdefer` for error paths when
  ownership transfers to the caller. Free allocations with the allocator that created them.
- Close owned I/O handles on all exit paths, using the same I/O context that opened them.
- Initialize permissions explicitly, such as `.default_dir` when creating a directory;
  never pass `undefined` for options that an API reads.
- Use `std.debug.assert` where invariants help correctness.
- In tests, name the test allocator `const test_gpa = std.testing.allocator;`.
- Route project imports in `src/main.zig` through `src/root.zig` (the `msort` module).
  Standard-library imports are allowed.

## Code style

- Use `snake_case` for project-defined functions and `PascalCase` for structs and types.
  Keep standard-library and dependency API names unchanged.
- Follow `zig fmt` output and keep Zig source lines at most **100 characters**;
  multiline string literals are the only exception.
- Wrap long argument and field lists with trailing commas inside `(...)` or `{...}` so
  `zig fmt` can wrap them naturally.
- Remove temporary `std.debug.print` calls before finishing.

## Required checks after changes

- Before finishing any change, read and follow the repository's
  [zig-formatting skill](.agents/skills/zig-formatting/SKILL.md), including its `zig fmt`
  and line-length checks. If the agent has no skill runner, follow the file's steps directly.
- **Always run `zig build test` from the repository root after making changes**, including
  documentation or agent-instruction changes, and fix failures before considering the work done.
  Run the tests after the final formatting pass so they validate the final files.
- For Zig code or build-script changes, also run `zig build` to check the executable.
  Use `zig build test --release=safe` when validating ReleaseSafe behavior.
- Report which checks passed and disclose any check that could not be run.
