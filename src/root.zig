pub const printer = @import("printer.zig");
pub const argparse = @import("argparse.zig");
pub const settings = @import("settings.zig");
const line = @import("line.zig");
pub const sort = @import("sort.zig");
const input = @import("input.zig");
const output = @import("output.zig");
const merge = @import("merge.zig");

pub const Args = argparse.Args;
pub const Settings = settings.Settings;
const Line = line.Line;
pub const Input = input.Input;
pub const Output = output.Output;
pub const Merge = merge.Merge;

test {
    _ = @import("cmp.zig");
    _ = argparse;
    _ = settings;
    _ = line;
    _ = sort;
    _ = input;
    _ = output;
    _ = merge;
}
