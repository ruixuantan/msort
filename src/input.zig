const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const settings = @import("settings.zig");
const simd = @import("simd.zig");
const Settings = settings.Settings;
const Key = settings.Key;
const line = @import("line.zig");
const Line = line.Line;
const LineTable = line.LineTable;

pub const Input = struct {
    gpa: mem.Allocator,
    s: *const Settings,
    buffer: []u8,
    lines: std.ArrayList(Line),
    file: fs.File,
    reader: fs.File.Reader,
    file_index: usize = 0,

    pub fn init(
        gpa: mem.Allocator,
        s: *const Settings,
        buffer: []u8,
        line_table_size: usize,
    ) !Input {
        const line_table_capacity = @divFloor(line_table_size, Line.size());
        const lines = try std.ArrayList(Line).initCapacity(gpa, line_table_capacity);
        var file: fs.File = undefined;
        if (s.files) |filenames| {
            file = try fs.cwd().openFile(filenames[0], .{ .mode = .read_only });
        } else {
            file = fs.File.stdin();
        }
        return .{
            .gpa = gpa,
            .s = s,
            .buffer = buffer,
            .lines = lines,
            .file = file,
            .reader = file.reader(buffer),
        };
    }

    inline fn max_file_index(self: *const Input) usize {
        return if (self.s.files) |files| files.len - 1 else 0;
    }

    pub fn deinit(self: *Input) void {
        self.file.close();
        self.lines.deinit(self.gpa);
    }

    inline fn is_at_eof(self: *Input) bool {
        return self.reader.interface.peek(1) == error.EndOfStream;
    }

    pub fn has_next(self: *Input) bool {
        return self.file_index < self.max_file_index() or !self.is_at_eof();
    }

    pub fn next(self: *Input) !LineTable {
        std.debug.assert(self.has_next());
        self.lines.clearRetainingCapacity();
        if (self.s.files != null and self.is_at_eof()) {
            self.file.close();
            self.file_index += 1;
            self.file = try fs.cwd().openFile(
                self.s.files.?[self.file_index],
                .{ .mode = .read_only },
            );
            self.reader = self.file.reader(self.buffer);
        }
        // fill the buffer
        _ = self.reader.interface.peek(@min(
            self.buffer.len,
            self.reader.interface.end - self.reader.interface.seek + 1,
        )) catch {};

        const string = self.reader.interface.peek(
            self.reader.interface.end - self.reader.interface.seek,
        ) catch unreachable;

        var i: usize = 0;
        var prev = i;
        while (i < string.len and self.lines.items.len < self.lines.capacity) : (i += 1) {
            if (string[i] == self.s.delimiter) {
                self.lines.appendAssumeCapacity(
                    Line.init(string[prev..i], prev, self.s.first_key, self.s.separator),
                );
                prev = i + 1;
            }
        }

        if (string[i - 1] != self.s.delimiter and
            self.reader.interface.end < self.buffer.len - 1 and
            self.lines.items.len < self.lines.capacity)
        {
            // handle case where last line is not terminated by the delimiter
            @branchHint(.cold);
            self.lines.appendAssumeCapacity(
                Line.init(
                    string[prev..i],
                    prev,
                    self.s.first_key,
                    self.s.separator,
                ),
            );
            prev = i;
        }

        return .{
            .lines = self.lines.items,
            .contents = self.reader.interface.take(prev) catch unreachable,
        };
    }
};

fn test_next_helper(
    gpa: std.mem.Allocator,
    buffer: []u8,
    paths: []const []const u8,
    line_table_size: usize,
) !void {
    std.debug.assert(paths.len > 0);

    const file_parts = try gpa.alloc([]const u8, paths.len);
    defer {
        for (file_parts) |p| gpa.free(p);
        gpa.free(file_parts);
    }
    for (paths, 0..) |p, i| {
        const file = try std.fs.cwd().openFile(p, .{ .mode = .read_only });
        defer file.close();
        file_parts[i] = try file.readToEndAlloc(gpa, 1024);
    }

    const s = Settings{ .files = paths };
    var input = try Input.init(gpa, &s, buffer, line_table_size);
    defer input.deinit();

    var buffer_builder: std.ArrayList(u8) = .empty;
    defer buffer_builder.deinit(gpa);
    while (input.has_next()) {
        const line_table = try input.next();
        const file_idx = input.file_index;
        for (line_table.lines) |l| {
            const off: usize = @intCast(l.offset);
            const len: usize = @intCast(l.length);
            const part = file_parts[file_idx];
            try buffer_builder.appendSlice(gpa, line_table.contents[off..][0..len]);
            if (off + len < part.len) {
                try buffer_builder.append(gpa, line_table.contents[off + len]);
            }
        }
    }

    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    for (file_parts) |part| {
        try expected.appendSlice(gpa, part);
    }
    try std.testing.expectEqualStrings(expected.items, buffer_builder.items);
}

test "Input: next, test_26.txt" {
    const test_gpa = std.testing.allocator;
    const buffer = try test_gpa.alloc(u8, 1024);
    defer test_gpa.free(buffer);
    try test_next_helper(
        test_gpa,
        buffer,
        &[_][]const u8{"test_data/test_26.txt"},
        26 * Line.size(),
    );
}

test "Input: next, test_26.txt, line_table_size 10 lines" {
    const test_gpa = std.testing.allocator;
    const buffer = try test_gpa.alloc(u8, 1024);
    defer test_gpa.free(buffer);
    try test_next_helper(
        test_gpa,
        buffer,
        &[_][]const u8{"test_data/test_26.txt"},
        10 * Line.size(),
    );
}

test "Input: next, test_26.txt, line_table 26, buffer 30" {
    const test_gpa = std.testing.allocator;
    const buffer = try test_gpa.alloc(u8, 30);
    defer test_gpa.free(buffer);
    try test_next_helper(
        test_gpa,
        buffer,
        &[_][]const u8{"test_data/test_26.txt"},
        26 * Line.size(),
    );
}

test "Input: next, test_26.txt and test_additional.txt" {
    const test_gpa = std.testing.allocator;
    const buffer = try test_gpa.alloc(u8, 1024);
    defer test_gpa.free(buffer);
    try test_next_helper(
        test_gpa,
        buffer,
        &[_][]const u8{ "test_data/test_26.txt", "test_data/test_additional.txt" },
        1024 * Line.size(),
    );
}
