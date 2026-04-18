const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const Settings = @import("settings.zig").Settings;
const line = @import("line.zig");
const Line = line.Line;
const LineTable = line.LineTable;

pub const Output = struct {
    gpa: Allocator,
    io: Io,
    buffer: []u8,
    s: *const Settings,

    pub fn init(gpa: Allocator, io: Io, s: *const Settings, buffer: []u8) !Output {
        return .{
            .gpa = gpa,
            .io = io,
            .buffer = buffer,
            .s = s,
        };
    }

    pub fn get_writer(self: *Output) !File.Writer {
        if (self.s.outfile) |o| {
            var file: File = undefined;
            file = Dir.cwd().openFile(self.io, o, .{ .mode = .write_only }) catch |err| switch (err) {
                error.FileNotFound => try Dir.cwd().createFile(self.io, o, .{}),
                else => |e| return e,
            };
            return file.writer(self.io, self.buffer);
        } else {
            return File.stdout().writer(self.io, self.buffer);
        }
    }

    fn write_lines(
        self: *Output,
        writer: *File.Writer,
        line_table: LineTable,
    ) !void {
        var buf_size: usize = 0;
        for (line_table.lines) |l| {
            const string = l.string(line_table.contents);
            if (buf_size + string.len + 1 > self.buffer.len) {
                @branchHint(.unlikely);
                try writer.interface.flush();
                buf_size = 0;
            }
            buf_size += string.len + 1;
            try writer.interface.writeAll(string);
            try writer.interface.writeByte(self.s.delimiter);
        }
        try writer.interface.flush();
    }

    fn write_unique_lines(
        self: *Output,
        writer: *File.Writer,
        line_table: LineTable,
    ) !void {
        var prev = line_table.lines[0];
        var string = prev.string(line_table.contents);
        var buf_size: usize = string.len + 1;
        try writer.interface.writeAll(string);
        try writer.interface.writeByte(self.s.delimiter);

        for (line_table.lines[1..]) |l| {
            string = l.string(line_table.contents);
            if (buf_size + string.len + 1 > self.buffer.len) {
                @branchHint(.unlikely);
                try writer.interface.flush();
                buf_size = 0;
            }
            if (Line.cmp(self.s, prev, line_table.contents, l, line_table.contents) == 0) {
                continue;
            }
            prev = l;
            buf_size += string.len + 1;
            try writer.interface.writeAll(string);
            try writer.interface.writeByte(self.s.delimiter);
        }
        try writer.interface.flush();
    }

    pub fn write_to_file(self: *Output, line_table: LineTable) !void {
        var writer = try self.get_writer();
        if (self.s.unique) {
            try self.write_unique_lines(&writer, line_table);
        } else {
            try self.write_lines(&writer, line_table);
        }
    }

    pub fn create_tmp_dir(self: *Output) !void {
        Dir.cwd().createDir(self.io, self.s.tmp_dir, undefined) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            }
        };
    }

    pub fn cleanup(self: *Output) void {
        Dir.cwd().deleteTree(self.io, self.s.tmp_dir) catch {};
    }

    pub fn write_to_tmp(self: *Output, line_table: LineTable, run: usize) !void {
        const tmp_file_name = try std.fmt.allocPrint(
            self.gpa,
            "{s}/{d}.tmp",
            .{ self.s.tmp_dir, run },
        );
        defer self.gpa.free(tmp_file_name);
        var writer = (try Dir.cwd().createFile(
            self.io,
            tmp_file_name,
            .{},
        )).writer(self.io, self.buffer);
        if (self.s.unique) {
            try self.write_unique_lines(&writer, line_table);
        } else {
            try self.write_lines(&writer, line_table);
        }
    }
};
