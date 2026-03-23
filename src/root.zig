const argparse = @import("argparse.zig");
const line = @import("line.zig");
const input = @import("input.zig");
pub const sort = @import("sort.zig");
const output = @import("output.zig");
const merge = @import("merge.zig");

pub const Args = argparse.Args;
pub const Input = input.Input;
pub const Output = output.Output;
pub const Merge = merge.Merge;

test {
    _ = argparse;
    _ = line;
    _ = input;
    _ = output;
    _ = sort;
    _ = merge;
}
