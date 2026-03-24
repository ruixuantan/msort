const std = @import("std");
const build_options = @import("build_options");
const line = @import("line.zig");

fn print_version(writer: *std.fs.File.Writer) !void {
    try writer.interface.print("{s}\n", .{build_options.version});
    try writer.interface.flush();
}

fn print_usage(writer: *std.fs.File.Writer) !void {
    const usage =
        \\Usage: msort [-kPOS1[,POS2] ... ] [-S memsize] [-T tmpdir] [-o outfile] [-r] [-t separator] [--qsort] [file ...]
        \\
        \\Mini sort implementation in Zig, defaulting to lexicographic order merge sort.
        \\
        \\Options:
        \\  -k          Key positions to sort by. Positions are 1-indexed and separated by commas
        \\  -S          Maximum memory size used to run msort. Units: K,M,G
        \\  -T          Write temporary files to specified directory, if sort file does not fit in memory
        \\  -o          Write output to file, instead of stdout
        \\  -r          Reverse the order of the sort
        \\  -t          Use specified separator for fields
        \\
        \\Other options:
        \\  --qsort     Use quicksort algorithm
        \\
        \\Arguments:
        \\  file ...    File(s) to sort. If no files are provided, stdin is used.
    ;
    try writer.interface.print("{s}\n", .{usage});
    try writer.interface.flush();
}

fn print_error(writer: *std.fs.File.Writer, err: []const u8) !void {
    try writer.interface.print("Error: {s}\n", .{err});
    try writer.interface.flush();
}

pub const SortAlgorithm = enum {
    mergesort,
    quicksort,
};

pub const Args = struct {
    cmp_algorithm: line.LineCmp = line.Line.lexicographic_cmp,
    keys: []const line.Key = undefined,
    memsize: usize = 8 * 1024 * 1024,
    tmp_dir: []const u8 = "tmp",
    outfile: ?[]const u8 = null,
    separator: u8 = ' ',
    sort_algorithm: SortAlgorithm = .mergesort,
    filenames: ?[]const []const u8 = null,
    delimiter: u8 = '\n',

    pub fn deinit(self: Args, gpa: std.mem.Allocator) void {
        if (self.filenames != null) gpa.free(self.filenames.?);
        gpa.free(self.keys);
    }

    fn parse_memsize(str: []const u8) !usize {
        const value = try std.fmt.parseInt(usize, str[0 .. str.len - 1], 10);
        const memsize = switch (str[str.len - 1]) {
            'K' => value * 1024,
            'M' => value * 1024 * 1024,
            'G' => value * 1024 * 1024 * 1024,
            else => return error.InvalidMemsize,
        };
        if (memsize > std.math.maxInt(u32)) return error.InvalidMemsize;
        return memsize;
    }

    fn parse_key(str: []const u8) !line.Key {
        var parts = std.mem.splitScalar(u8, str, ',');
        var start: usize = undefined;
        if (parts.next()) |start_str| {
            start = try std.fmt.parseInt(usize, start_str, 10);
        } else return error.InvalidKey;

        var end: usize = 0;
        if (parts.next()) |end_str| {
            end = try std.fmt.parseInt(usize, end_str, 10);
            if (start > end) return error.InvalidKey;
            end = end + 1; // make end exclusive
        }
        return .{ .start = start, .end = end };
    }

    fn parse_flags(self: *Args, gpa: std.mem.Allocator, argv: []const [:0]u8, i: *usize) !bool {
        var keys: std.ArrayList(line.Key) = .empty;
        defer keys.deinit(gpa);

        while (i.* < argv.len) : (i.* += 1) {
            const arg = argv[i.*];
            if (arg.len == 0 or arg[0] != '-') break;

            if (std.mem.eql(u8, arg, "-k")) {
                i.* += 1;
                if (i.* >= argv.len) return false;
                const key_str = argv[i.*];
                try keys.append(gpa, parse_key(key_str) catch return false);
            } else if (std.mem.eql(u8, arg, "-S")) {
                i.* += 1;
                if (i.* >= argv.len) return false;
                self.memsize = parse_memsize(argv[i.*]) catch return false;
            } else if (std.mem.eql(u8, arg, "-T")) {
                i.* += 1;
                if (i.* >= argv.len) return false;
                self.tmp_dir = argv[i.*];
            } else if (std.mem.eql(u8, arg, "-o")) {
                i.* += 1;
                if (i.* >= argv.len) return false;
                self.outfile = argv[i.*];
            } else if (std.mem.eql(u8, arg, "-t")) {
                i.* += 1;
                if (i.* >= argv.len) return false;
                self.separator = argv[i.*][0];
            } else if (std.mem.eql(u8, arg, "-r")) {
                self.cmp_algorithm = line.Line.rlexicographic_cmp;
            } else if (std.mem.eql(u8, arg, "--qsort")) {
                self.sort_algorithm = .quicksort;
            } else {
                return false;
            }
        }
        if (keys.items.len == 0) try keys.append(gpa, .{ .start = 1, .end = 0 });
        self.keys = try keys.toOwnedSlice(gpa);
        return true;
    }

    pub fn parse(gpa: std.mem.Allocator, args: []const [:0]u8, writer: *std.fs.File.Writer) !?Args {
        var parsed_args: Args = .{};
        if (args.len == 1) return parsed_args;
        if (std.mem.eql(u8, args[1], "--help")) {
            try print_usage(writer);
            return null;
        } else if (std.mem.eql(u8, args[1], "--version")) {
            try print_version(writer);
            return null;
        }

        var i: usize = 1;
        if (!try parsed_args.parse_flags(gpa, args, &i)) {
            try print_error(writer, "Invalid flags");
            return error.ArgParseError;
        }

        var files: std.ArrayList([]const u8) = .empty;
        while (i < args.len) {
            try files.append(gpa, args[i]);
            i += 1;
        }
        parsed_args.filenames = try files.toOwnedSlice(gpa);
        if (parsed_args.filenames.?.len == 0) {
            try print_error(writer, "No files provided");
            gpa.free(parsed_args.filenames.?);
            return error.ArgParseError;
        }

        return parsed_args;
    }

    pub fn validate(self: Args, writer: *std.fs.File.Writer) !void {
        if (self.filenames) |filenames| {
            for (filenames) |filename| {
                var file = std.fs.cwd().openFile(filename, .{ .mode = .read_only }) catch |err| {
                    switch (err) {
                        error.FileNotFound => try print_error(writer, "No such file"),
                        error.AccessDenied => try print_error(writer, "Read access denied"),
                        else => return err,
                    }
                    return error.ValidationFailed;
                };
                defer file.close();
            }
        } else {
            const file = std.fs.File.stdin();
            const stat = try file.stat();
            if (stat.size == 0) try print_usage(writer);
        }
    }

    pub fn input_buffer_size(self: Args) usize {
        return self.memsize >> 1;
    }

    pub fn line_table_size(self: Args) usize {
        return self.memsize >> 2;
    }

    pub fn output_buffer_size(self: Args) usize {
        return self.memsize >> 3;
    }
};
