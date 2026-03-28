const std = @import("std");

pub const Key = struct { start: usize, end: usize, reverse: bool = false, numeric: bool = false };

pub const Line = struct {
    offset: u32,
    length: u32,
    key_offset: u32,
    key_length: u32,
    key_prefix: u32,

    pub fn get_key(
        raw: []const u8,
        key: Key,
        separator: u8,
    ) struct { offset: usize, length: usize } {
        var i: usize = 0;
        var field: usize = 1;
        while (field < key.start) : (field += 1) {
            while (i < raw.len and raw[i] != separator) : (i += 1) {}
            if (i < raw.len) {
                i += 1;
            } else {
                return .{ .offset = raw.len, .length = 0 };
            }
        }
        const start = i;

        if (key.end == 0) return .{ .offset = start, .length = raw.len - start };

        i = start;
        field = key.start;
        while (field < key.end) : (field += 1) {
            while (i < raw.len and raw[i] != separator) : (i += 1) {}
            if (field + 1 < key.end) {
                if (i < raw.len and raw[i] == separator) i += 1;
            }
        }
        return .{ .offset = start, .length = i - start };
    }

    pub fn init(raw: []const u8, offset: usize, key: Key, separator: u8) Line {
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

    pub fn size() usize {
        return @sizeOf(Line);
    }

    pub fn string(self: Line, buffer: []const u8) []const u8 {
        return buffer[@as(usize, self.offset)..][0..@as(usize, self.length)];
    }
};

pub const LineTable = struct {
    lines: []Line,
    contents: []const u8,
};

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
