const std = @import("std");
const Args = @import("argparse.zig").Args;
const Line = @import("line.zig").Line;
const LineTable = @import("line.zig").LineTable;

pub const Output = struct {
    gpa: std.mem.Allocator,
    buffer: []u8,
    args: *const Args,

    pub fn init(gpa: std.mem.Allocator, args: *const Args, buffer: []u8) !Output {
        return .{
            .gpa = gpa,
            .buffer = buffer,
            .args = args,
        };
    }

    pub fn get_writer(self: *Output) !std.fs.File.Writer {
        if (self.args.outfile != null) {
            return (try std.fs.cwd().createFile(self.args.outfile.?, .{})).writer(self.buffer);
        } else {
            return std.fs.File.stdout().writer(self.buffer);
        }
    }

    fn write_lines(
        self: *Output,
        writer: *std.fs.File.Writer,
        line_table: LineTable,
    ) !void {
        var buf_size: usize = 0;
        for (line_table.lines) |line| {
            const string = line.string(line_table.contents);
            if (buf_size + string.len + 1 > self.buffer.len) {
                @branchHint(.unlikely);
                try writer.interface.flush();
                buf_size = 0;
            }
            buf_size += string.len + 1;
            try writer.interface.writeAll(string);
            try writer.interface.writeByte(self.args.delimiter);
        }
        try writer.interface.flush();
    }

    pub fn write_to_file(self: *Output, line_table: LineTable) !void {
        var writer = try self.get_writer();
        try self.write_lines(&writer, line_table);
    }

    pub fn create_tmp_dir(self: *Output) !void {
        std.fs.cwd().makeDir(self.args.tmp_dir) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            }
        };
    }

    pub fn cleanup(self: *Output) void {
        std.fs.cwd().deleteTree(self.args.tmp_dir) catch {};
    }

    pub fn write_to_tmp(self: *Output, line_table: LineTable, run: usize) !void {
        const tmp_file_name = try std.fmt.allocPrint(
            self.gpa,
            "{s}/{d}.tmp",
            .{ self.args.tmp_dir, run },
        );
        defer self.gpa.free(tmp_file_name);
        var writer = (try std.fs.cwd().createFile(tmp_file_name, .{})).writer(self.buffer);
        try self.write_lines(&writer, line_table);
    }
};
