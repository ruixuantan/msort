const std = @import("std");

pub const Key = struct { start: usize, end: usize, reverse: bool = false, numeric: bool = false };

pub const Line = struct {
    offset: u32,
    length: u32,
    key_offset: u32,
    key_length: u32,
    key_prefix: u32,

    pub inline fn get_key_start_offset(buffer: []const u8, key: Key, separator: u8) usize {
        var i: usize = 0;
        var field: usize = 1;
        while (i < buffer.len and field < key.start) : (i += 1) {
            if (buffer[i] == separator) field += 1;
        }
        return i;
    }

    pub inline fn get_key(
        raw: []const u8,
        key: Key,
        separator: u8,
    ) struct { offset: usize, length: usize } {
        const start = get_key_start_offset(raw, key, separator);
        if (key.end == 0) return .{ .offset = start, .length = raw.len - start };
        var i = start;
        var field = key.start;
        while (i < raw.len and field < key.end) : (i += 1) {
            if (raw[i] == separator) field += 1;
        }
        return .{ .offset = start, .length = i - start - 1 };
    }

    pub inline fn init(raw: []const u8, offset: usize, key: Key, separator: u8) Line {
        var key_offset: usize = 0;
        var key_length: usize = raw.len;
        if (key.start != 1 or key.end != 0) {
            const key_info = get_key(raw, key, separator);
            key_offset = key_info.offset;
            key_length = key_info.length;
        }

        var prefix_bytes: [4]u8 = .{ 0, 0, 0, 0 };
        const n = @min(key_length, 4);
        @memcpy(prefix_bytes[0..n], raw[key_offset..][0..n]);
        const key_prefix = std.mem.readInt(u32, &prefix_bytes, .big);

        return .{
            .offset = @intCast(offset),
            .length = @intCast(raw.len),
            .key_offset = @intCast(offset + key_offset),
            .key_length = @intCast(key_length),
            .key_prefix = key_prefix,
        };
    }

    pub inline fn size() usize {
        return @sizeOf(Line);
    }

    pub inline fn string(self: Line, buffer: []const u8) []const u8 {
        return buffer[@as(usize, self.offset)..][0..@as(usize, self.length)];
    }
};

pub const LineTable = struct {
    lines: []Line,
    contents: []const u8,
};

test "line: get_key_start_offset" {
    const raw = "cherry,0.1,,2";
    const key1 = Key{ .start = 1, .end = 4 };
    const key2 = Key{ .start = 2, .end = 4 };
    const key3 = Key{ .start = 3, .end = 4 };
    const key4 = Key{ .start = 4, .end = 4 };
    const sep: u8 = ',';
    try std.testing.expectEqual(0, Line.get_key_start_offset(raw, key1, sep));
    try std.testing.expectEqual(7, Line.get_key_start_offset(raw, key2, sep));
    try std.testing.expectEqual(11, Line.get_key_start_offset(raw, key3, sep));
    try std.testing.expectEqual(12, Line.get_key_start_offset(raw, key4, sep));
}

test "line: with key (-k 2,3 with -t ,)" {
    const raw =
        \\3,cherry,0.1,
        \\1,apple,0.3,red
        \\2,banana,0.2,yellow
        \\
    ;
    const key = Key{ .start = 2, .end = 4 };
    const sep: u8 = ',';
    const line1 = Line.init(raw[0..14], 0, key, sep);
    const line2 = Line.init(raw[14..30], 14, key, sep);
    const line3 = Line.init(raw[30..50], 30, key, sep);
    try std.testing.expectEqualStrings("cherry,0.1", raw[line1.key_offset..][0..line1.key_length]);
    try std.testing.expectEqualStrings("apple,0.3", raw[line2.key_offset..][0..line2.key_length]);
    try std.testing.expectEqualStrings("banana,0.2", raw[line3.key_offset..][0..line3.key_length]);
}
