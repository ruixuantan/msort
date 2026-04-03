const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const settings = @import("settings.zig");
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
    file_pos: usize = 0,
    file_size: usize,

    pub fn init(
        gpa: mem.Allocator,
        s: *const Settings,
        buffer: []u8,
        line_table_size: usize,
    ) !Input {
        const line_table_capacity = @divFloor(line_table_size, Line.size());
        const line_table = try std.ArrayList(Line).initCapacity(gpa, line_table_capacity);
        var file: fs.File = undefined;
        var file_size: usize = undefined;
        if (s.files) |filenames| {
            file = try fs.cwd().openFile(filenames[0], .{ .mode = .read_only });
        } else {
            file = fs.File.stdin();
        }
        file_size = (try file.stat()).size;

        return .{
            .gpa = gpa,
            .s = s,
            .buffer = buffer,
            .lines = line_table,
            .file = file,
            .reader = file.reader(buffer),
            .file_size = @intCast(file_size),
        };
    }

    inline fn max_file_index(self: *const Input) usize {
        return if (self.s.files) |files| files.len - 1 else 0;
    }

    pub fn deinit(self: *Input) void {
        self.file.close();
        self.lines.deinit(self.gpa);
    }

    pub fn has_next(self: *Input) bool {
        return self.file_index < self.max_file_index() or self.file_pos < self.file_size;
    }

    pub fn next(self: *Input) !LineTable {
        std.debug.assert(self.has_next());
        self.lines.clearRetainingCapacity();

        if (self.s.files != null and self.file_pos == self.file_size) {
            self.file.close();
            self.file_index += 1;
            self.file = try fs.cwd().openFile(
                self.s.files.?[self.file_index],
                .{ .mode = .read_only },
            );
            self.reader = self.file.reader(self.buffer);
            self.file_pos = 0;
            self.file_size = @intCast((try self.file.stat()).size);
        }

        const contents = try self.reader.interface.peek(@min(
            self.file_size - self.file_pos,
            self.buffer.len,
        ));

        // TODO: Change to simd implementation
        var prev: usize = 0;
        var i: usize = 0;
        while (i < contents.len) : (i += 1) {
            if (self.lines.items.len == self.lines.capacity) {
                break;
            } else if (contents[i] == self.s.delimiter) {
                self.lines.appendAssumeCapacity(
                    Line.init(contents[prev..i], prev, self.s.first_key, self.s.separator),
                );
                prev = i + 1;
            } else if (i == contents.len - 1) {
                const at_eof = self.file_pos + contents.len >= self.file_size;
                if (at_eof) {
                    self.lines.appendAssumeCapacity(
                        Line.init(
                            contents[prev .. i + 1],
                            prev,
                            self.s.first_key,
                            self.s.separator,
                        ),
                    );
                    prev = i + 1;
                }
            }
        }
        const read_content = try self.reader.interface.take(prev);
        self.file_pos += prev;
        return .{
            .lines = self.lines.items,
            .contents = read_content,
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
