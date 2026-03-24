---
name: zig-formatting
description: Runs zig fmt and enforces a 100-character line limit by adding trailing commas inside parentheses and braces so arguments wrap. Use when formatting Zig code, editing .zig files, or when the user mentions zig fmt, formatting, or line length in Zig.
---

# Zig formatting

## Workflow

1. **Run `zig fmt`** on the touched files or the repo root (e.g. `zig fmt path/to/file.zig` or `zig fmt .` from the project root). Re-run after structural edits.
2. **Check line length**: no line may exceed **100** characters (including after `zig fmt`). Only multiline strings are allowed to exceed.
3. **If a line is still too long**: break the expression by inserting **trailing commas** in comma-separated lists inside **`(...)`** or **`{...}`** so the next `zig fmt` wraps arguments/fields onto separate lines. Prefer that over awkward manual splits that fight the formatter.
4. Lastly, run `zig build test` as a sanity check.

## Notes

- `zig fmt` is authoritative for spacing and brace style; the extra step is the **100-char cap** and using commas to give `zig fmt` natural break points.
- Apply the same rules to new code before finishing a change.
