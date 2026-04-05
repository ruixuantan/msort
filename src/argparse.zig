// Derived and learnt from: https://github.com/tigerbeetle/tigerbeetle/blob/main/src/stdx/flags.zig
const std = @import("std");
const build_options = @import("build_options");
const assert = std.debug.assert;
const mem = std.mem;
const printer = @import("printer.zig");

pub const Memory = struct {
    value: usize,

    pub fn parse(str: []const u8) !Memory {
        const value = try std.fmt.parseInt(usize, str[0 .. str.len - 1], 10);
        const memsize = switch (str[str.len - 1]) {
            'K' => value * 1024,
            'M' => value * 1024 * 1024,
            'G' => value * 1024 * 1024 * 1024,
            else => {
                try printer.print_err("Invalid memory size: {s}\n", .{str});
                return error.InvalidMemsize;
            },
        };
        if (memsize > std.math.maxInt(u32)) {
            try printer.print_err("Memory size too large: {s}\n", .{str});
            return error.InvalidMemsize;
        }
        return .{ .value = memsize };
    }
};

pub fn parse_args(args: []const [:0]const u8, comptime CliArgs: type) !?CliArgs {
    comptime {
        assert(@typeInfo(CliArgs) == .@"struct");
        assert(@hasDecl(CliArgs, "help"));
        assert(@hasDecl(CliArgs, "version"));
    }
    var cli_args: CliArgs = .{};
    if (args.len == 1) return cli_args;
    if (mem.eql(u8, args[1], "--help") or mem.eql(u8, args[1], "-h")) {
        try printer.print(CliArgs.help);
        return null;
    }
    if (mem.eql(u8, args[1], "--version") or mem.eql(u8, args[1], "-v")) {
        try printer.print(CliArgs.version);
        return null;
    }

    for (args[1..], 1..) |arg, i| {
        if (arg[0] == '-') {
            try parse_field(arg, CliArgs, &cli_args);
        } else {
            if (@hasField(CliArgs, "positional")) {
                @field(cli_args, "positional") = args[i..];
                break;
            }
        }
    }
    return cli_args;
}

inline fn flag_matches(comptime field_name: []const u8, arg: [:0]const u8) !bool {
    assert(arg.len > 1 and arg[0] == '-');
    if (arg[0] == '-' and arg[1] == field_name[0]) return true;
    if (mem.startsWith(u8, arg, "--" ++ field_name)) return true;
    return false;
}

inline fn parse_val(arg: [:0]const u8, comptime T: type) !T {
    var parts = mem.splitScalar(u8, arg, '=');
    assert(parts.next() != null);
    const val = parts.next() orelse {
        try printer.print_err("Invalid flag (missing '=value'): {s}\n", .{arg});
        return error.InvalidFlag;
    };
    return switch (T) {
        u8 => {
            if (val.len != 1) {
                try printer.print_err("Invalid flag (missing value): {s}\n", .{arg});
                return error.InvalidFlag;
            }
            return val[0];
        },
        []const u8 => val,
        Memory => try Memory.parse(val),
        else => @compileError("Unsupported field type: " ++ @typeName(T)),
    };
}

fn parse_field(arg: [:0]const u8, comptime CliArgs: type, cli_args: *CliArgs) !void {
    var parsed = false;
    inline for (std.meta.fields(CliArgs)) |field| {
        if (try flag_matches(field.name, arg)) {
            parsed = true;
            switch (@typeInfo(field.type)) {
                .bool => @field(cli_args, field.name) = true,
                .int, .pointer => @field(cli_args, field.name) = try parse_val(arg, field.type),
                .optional => |T| {
                    if (field.type != ?[]const [:0]const u8)
                        @field(cli_args, field.name) = try parse_val(arg, T.child);
                },
                .@"struct" => {
                    switch (field.type) {
                        Memory => @field(cli_args, field.name) = try parse_val(arg, field.type),
                        else => @compileError("Unsupported struct type: " ++ @typeName(field.type)),
                    }
                },
                else => @compileError("Unsupported field type: " ++ @typeName(field.type)),
            }
        }
    }
    if (!parsed) {
        try printer.print_err("Invalid flag: {s}\n", .{arg});
        return error.InvalidFlag;
    }
}

pub const Args = struct {
    algo: []const u8 = "mergesort",
    delimiter: u8 = '\n',
    keys: ?[]const u8 = null,
    memsize: Memory = .{ .value = 8 * 1024 * 1024 },
    numeric: bool = false,
    outfile: ?[]const u8 = null,
    reverse: bool = false,
    separator: u8 = ' ',
    tmp_dir: []const u8 = "tmp",
    unique: bool = false,

    positional: ?[]const [:0]const u8 = null,
    pub const version = build_options.version;
    pub const help =
        \\Usage: msort [options] [file(s) ...]
        \\
        \\Mini sort implementation in Zig, defaulting to lexicographic order merge sort.
        \\
        \\Options:
        \\  -a, --algo=[mergesort,quicksort]
        \\    Sort algorithm to use. Default: mergesort
        \\
        \\  -d, --delimiter=[char]
        \\    Sort delimiter. Default: '\n'
        \\
        \\  -k, --key=[pos1[,pos2] ...]
        \\    Key positions to sort by. Positions are 0-indexed and can be suffixed with 'r' for reverse and 'n' for numeric.
        \\    Multiple positions are separated by commas. Range key sorting is not supported.
        \\
        \\  -m, --memsize=[string]
        \\    Maximum memory size used to run msort. Units: K,M,G. Default: 8M
        \\
        \\  -n, --numeric
        \\    Use numeric comparison for sorting. Default: false
        \\
        \\  -o, --outfile=[file]
        \\    Write output to file, instead of stdout
        \\
        \\  -r, --reverse
        \\    Reverse the order of the sort. Default: false
        \\
        \\  -s, --separator=[char]
        \\    Key separator. Used in conjunction with -k. Default: ' '
        \\
        \\  -t, --tmp_dir=[dir]
        \\    Write temporary files to specified directory, if sort file does not fit in memory. Default: 'tmp'
        \\
        \\  -u, --unique
        \\    Removes duplicate lines. Default: false
        \\
        \\Misc options:
        \\  -h, --help
        \\    Print this help message and exit
        \\
        \\  -v, --version
        \\    Print the version and exit
        \\
        \\Arguments:
        \\  file(s) ...
        \\    File(s) to sort. If no files are provided, stdin is used.
    ;
};

test "Args: parse" {
    const raw_basic: []const [:0]const u8 = &.{ "msort", "file1.txt", "file2.txt" };
    const args_basic = try parse_args(raw_basic, Args);
    try std.testing.expectEqualStrings("file1.txt", args_basic.?.positional.?[0]);
    try std.testing.expectEqualStrings("file2.txt", args_basic.?.positional.?[1]);

    const raw_boolean: []const [:0]const u8 = &.{ "msort", "-u", "file1.txt" };
    const args_boolean = try parse_args(raw_boolean, Args);
    try std.testing.expect(args_boolean.?.unique);

    const raw_values: []const [:0]const u8 = &.{
        "msort",
        "-t=newtmp",
        "--memsize=1G",
        "-o=out.out",
        "file1.txt",
    };
    const args_values = try parse_args(raw_values, Args);
    try std.testing.expectEqualStrings("newtmp", args_values.?.tmp_dir);
    try std.testing.expectEqual(1 * 1024 * 1024 * 1024, args_values.?.memsize.value);
    try std.testing.expectEqualStrings("out.out", args_values.?.outfile.?);
}
