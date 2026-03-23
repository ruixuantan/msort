const std = @import("std");
const build_options = @import("build_options");

fn print_version(writer: *std.fs.File.Writer) !void {
    try writer.interface.print("{s}\n", .{build_options.version});
    try writer.interface.flush();
}

fn print_usage(writer: *std.fs.File.Writer) !void {
    const usage =
        \\Usage: msort [-o outfile] [-T tmpdir] [--qsort] [file ...]
        \\
        \\Mini sort implementation in Zig.
        \\
        \\Options:
        \\  -o          Write output to file, instead of stdout
        \\  -T          Write temporary files to specified directory
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
    outfile: ?[]const u8 = null,
    filenames: ?[]const []const u8 = null,
    delimiter: u8 = '\n',
    sort_algorithm: SortAlgorithm = .mergesort,
    tmp_dir: []const u8 = "tmp",

    pub fn deinit(self: Args, gpa: std.mem.Allocator) void {
        if (self.filenames != null) gpa.free(self.filenames.?);
    }

    fn parse_flags(self: *Args, argv: []const [:0]u8, i: *usize) !bool {
        while (i.* < argv.len) {
            const arg = argv[i.*];
            if (arg.len == 0 or arg[0] != '-') break;

            if (std.mem.eql(u8, arg, "-o")) {
                i.* += 1;
                if (i.* >= argv.len) return false;
                self.outfile = argv[i.*];
                i.* += 1;
            } else if (std.mem.eql(u8, arg, "-T")) {
                i.* += 1;
                if (i.* >= argv.len) return false;
                self.tmp_dir = argv[i.*];
                i.* += 1;
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

    pub fn debug_print(self: Args) void {
        std.debug.print("outfile: {any}\n", .{self.outfile});
        std.debug.print("tmpdir: {s}\n", .{self.tmp_dir});
        if (self.filenames != null) {
            for (self.filenames.?) |filename| {
                std.debug.print("filename: {s}\n", .{filename});
            }
        }
    }
};
