const std = @import("std");
const build_options = @import("build_options");
const line = @import("line.zig");

fn print_version(writer: *std.fs.File.Writer) !void {
    try writer.interface.print("{s}\n", .{build_options.version});
    try writer.interface.flush();
}

fn print_usage(writer: *std.fs.File.Writer) !void {
    const usage =
        \\Usage: msort [-S memsize] [-T tmpdir] [-o outfile] [-r] [--qsort] [file ...]
        \\
        \\Mini sort implementation in Zig, defaulting to lexicographic order merge sort.
        \\
        \\Options:
        \\  -S          Maximum memory size used to run msort. Units: K,M,G
        \\  -T          Write temporary files to specified directory, if sort file does not fit in memory
        \\  -o          Write output to file, instead of stdout
        \\  -r          Reverse the order of the sort
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
    memsize: usize = 8 * 1024 * 1024,
    tmp_dir: []const u8 = "tmp",
    outfile: ?[]const u8 = null,
    sort_algorithm: SortAlgorithm = .mergesort,
    filenames: ?[]const []const u8 = null,
    delimiter: u8 = '\n',

    pub fn deinit(self: Args, gpa: std.mem.Allocator) void {
        if (self.filenames != null) gpa.free(self.filenames.?);
    }

    fn parse_memsize(str: []const u8) !usize {
        const value = try std.fmt.parseInt(usize, str[0 .. str.len - 1], 10);
        switch (str[str.len - 1]) {
            'K' => return value * 1024,
            'M' => return value * 1024 * 1024,
            'G' => return value * 1024 * 1024 * 1024,
            else => return error.InvalidMemsize,
        }
    }

    fn parse_flags(self: *Args, argv: []const [:0]u8, i: *usize) !bool {
        while (i.* < argv.len) {
            const arg = argv[i.*];
            if (arg.len == 0 or arg[0] != '-') break;

            if (std.mem.eql(u8, arg, "-S")) {
                i.* += 1;
                if (i.* >= argv.len) return false;
                self.memsize = parse_memsize(argv[i.*]) catch return false;
                i.* += 1;
            } else if (std.mem.eql(u8, arg, "-T")) {
                i.* += 1;
                if (i.* >= argv.len) return false;
                self.tmp_dir = argv[i.*];
                i.* += 1;
            } else if (std.mem.eql(u8, arg, "-o")) {
                i.* += 1;
                if (i.* >= argv.len) return false;
                self.outfile = argv[i.*];
                i.* += 1;
            } else if (std.mem.eql(u8, arg, "-r")) {
                i.* += 1;
                self.cmp_algorithm = line.Line.rlexicographic_cmp;
            } else if (std.mem.eql(u8, arg, "--qsort")) {
                i.* += 1;
                self.sort_algorithm = .quicksort;
            }
        }
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
        if (!try parsed_args.parse_flags(args, &i)) {
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
