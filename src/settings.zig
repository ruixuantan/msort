const std = @import("std");
const mem = std.mem;
const Args = @import("argparse.zig").Args;
const printer = @import("printer.zig");

pub const CmpType = enum {
    lexicographic,
    numeric,
};

pub const Key = struct {
    pos: usize,
    reverse: i8 = 1,
    cmp_type: CmpType = .lexicographic,

    pub fn from_str(gpa: mem.Allocator, str: []const u8) ![]const Key {
        var ls: std.ArrayList(Key) = .empty;
        errdefer ls.deinit(gpa);
        var parts = mem.splitScalar(u8, str, ',');
        while (parts.next()) |part| {
            var reverse: i8 = 1;
            var cmp_type: CmpType = .lexicographic;
            var i: usize = part.len - 1;
            while (i > 0) : (i -= 1) {
                switch (part[i]) {
                    'r' => reverse = -1,
                    'n' => cmp_type = .numeric,
                    '0'...'9' => break,
                    else => {
                        try printer.print_err("Invalid key: {s}\n", .{str});
                        return error.InvalidKey;
                    },
                }
            }
            try ls.append(gpa, .{
                .pos = try std.fmt.parseInt(usize, part[0 .. i + 1], 10),
                .reverse = reverse,
                .cmp_type = cmp_type,
            });
        }
        return try ls.toOwnedSlice(gpa);
    }
};

pub const Algo = enum {
    mergesort,
    quicksort,

    pub fn from_str(str: []const u8) !Algo {
        if (mem.eql(u8, str, "mergesort")) return .mergesort;
        if (mem.eql(u8, str, "quicksort")) return .quicksort;
        try printer.print_err("Invalid sort algorithm: {s}\n", .{str});
        return error.InvalidAlgo;
    }
};

pub const Settings = struct {
    algo: Algo = .mergesort,
    delimiter: u8 = '\n',
    first_key: ?Key = null,
    keys: ?[]const Key = null,
    memsize: usize = 8 * 1024 * 1024,
    cmp_type: CmpType = .lexicographic,
    outfile: ?[]const u8 = null,
    reverse: i8 = 1,
    separator: u8 = ' ',
    tmp_dir: []const u8 = "tmp",
    unique: bool = false,
    files: ?[]const []const u8 = null,

    fn validate_files(files: []const [:0]const u8) !void {
        for (files) |filename| {
            var file = std.fs.cwd().openFile(filename, .{ .mode = .read_only }) catch |err| {
                switch (err) {
                    error.FileNotFound => try printer.print_err("No such file: {s}", .{filename}),
                    error.AccessDenied => try printer.print_err(
                        "Read access denied: {s}",
                        .{filename},
                    ),
                    else => return err,
                }
                return error.ValidationFailed;
            };
            defer file.close();
        }
    }

    pub fn from_args(gpa: mem.Allocator, args: *const Args) !Settings {
        if (args.positional) |files| try validate_files(files);
        const keys = if (args.keys) |k_str| try Key.from_str(gpa, k_str) else null;
        return .{
            .algo = try Algo.from_str(args.algo),
            .delimiter = args.delimiter,
            .first_key = if (keys) |ks| ks[0] else null,
            .keys = keys,
            .memsize = args.memsize.value,
            .cmp_type = if (args.numeric) .numeric else .lexicographic,
            .outfile = args.outfile,
            .reverse = if (args.reverse) -1 else 1,
            .separator = args.separator,
            .tmp_dir = args.tmp_dir,
            .unique = args.unique,
            .files = args.positional,
        };
    }

    pub fn deinit(self: Settings, gpa: mem.Allocator) void {
        if (self.keys) |keys| gpa.free(keys);
    }

    pub fn input_buffer_size(self: Settings) usize {
        return self.memsize >> 1;
    }

    pub fn line_table_size(self: Settings) usize {
        return self.memsize >> 2;
    }

    pub fn output_buffer_size(self: Settings) usize {
        return self.memsize >> 3;
    }
};

test "Key: from_str" {
    const gpa = std.testing.allocator;
    const single_key = try Key.from_str(gpa, "1");
    defer gpa.free(single_key);
    try std.testing.expectEqual(single_key[0].pos, 1);

    const multiple_keys = try Key.from_str(gpa, "1,2,3");
    defer gpa.free(multiple_keys);
    try std.testing.expectEqual(multiple_keys[0].pos, 1);
    try std.testing.expectEqual(multiple_keys[1].pos, 2);
    try std.testing.expectEqual(multiple_keys[2].pos, 3);

    const multiple_with_options = try Key.from_str(gpa, "1r,2n,3");
    defer gpa.free(multiple_with_options);
    try std.testing.expectEqual(multiple_with_options[0].pos, 1);
    try std.testing.expectEqual(multiple_with_options[0].reverse, -1);
    try std.testing.expectEqual(multiple_with_options[1].pos, 2);
    try std.testing.expectEqual(multiple_with_options[1].cmp_type, .numeric);
    try std.testing.expectEqual(multiple_with_options[2].pos, 3);
    try std.testing.expectEqual(multiple_with_options[2].cmp_type, .lexicographic);
}

test "settings" {
    const gpa = std.testing.allocator;
    const args = Args{
        .algo = "mergesort",
        .delimiter = '\n',
        .keys = "1,2,3",
        .memsize = .{ .value = 8 * 1024 * 1024 },
        .numeric = false,
        .outfile = null,
        .reverse = false,
    };
    const settings = try Settings.from_args(gpa, &args);
    defer settings.deinit(gpa);
}
