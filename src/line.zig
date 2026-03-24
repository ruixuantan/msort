const std = @import("std");

const Args = @import("argparse.zig").Args;

pub const Key = struct { start: usize, end: usize };

pub const Line = struct {
    offset: u32,
    length: u32,
    key_offset: u32,
    key_length: u32,
    key_prefix: u32,

    fn get_key(raw: []const u8, key: Key, separator: u8) struct { offset: usize, length: usize } {
        if (key.start == 1 and key.end == 0) return .{ .offset = 0, .length = raw.len };
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
        const key_info = get_key(raw, key, separator);

        var prefix_bytes: [4]u8 = .{ 0, 0, 0, 0 };
        const n = @min(key_info.length, 4);
        @memcpy(prefix_bytes[0..n], raw[key_info.offset..][0..n]);
        const key_prefix = std.mem.readInt(u32, &prefix_bytes, .big);

        return .{
            .offset = @intCast(offset),
            .length = @intCast(raw.len),
            .key_offset = @intCast(offset + key_info.offset),
            .key_length = @intCast(key_info.length),
            .key_prefix = key_prefix,
        };
    }

    pub fn size() usize {
        return @sizeOf(Line);
    }

    pub fn lexicographic_cmp(
        args: *const Args,
        x: Line,
        x_buffer: []const u8,
        y: Line,
        y_buffer: []const u8,
    ) std.math.Order {
        const by_prefix = std.math.order(x.key_prefix, y.key_prefix);
        if (by_prefix != .eq) return by_prefix;
        {
            const x_key = x_buffer[@as(usize, x.key_offset)..][0..@as(usize, x.key_length)];
            const y_key = y_buffer[@as(usize, y.key_offset)..][0..@as(usize, y.key_length)];
            const key_order = std.mem.order(u8, x_key, y_key);
            if (key_order != .eq) return key_order;
        }

        for (args.keys[1..]) |key| {
            const x_key_info = get_key(x_buffer, key, args.separator);
            const y_key_info = get_key(y_buffer, key, args.separator);
            const x_slice = x_buffer[@as(usize, x.key_offset + x_key_info.offset)..];
            const y_slice = y_buffer[@as(usize, y.key_offset + y_key_info.offset)..];
            const x_key = x_slice[0..@as(usize, x_key_info.length)];
            const y_key = y_slice[0..@as(usize, y_key_info.length)];
            const key_order = std.mem.order(u8, x_key, y_key);
            if (key_order != .eq) return key_order;
        }

        const x_str = x_buffer[@as(usize, x.offset)..][0..@as(usize, x.length)];
        const y_str = y_buffer[@as(usize, y.offset)..][0..@as(usize, y.length)];
        return std.mem.order(u8, x_str, y_str);
    }

    pub fn rlexicographic_cmp(
        args: *const Args,
        x: Line,
        x_buffer: []const u8,
        y: Line,
        y_buffer: []const u8,
    ) std.math.Order {
        _ = args;
        const by_prefix = std.math.order(y.key_prefix, x.key_prefix);
        if (by_prefix != .eq) return by_prefix;

        const x_key = x_buffer[@as(usize, x.key_offset)..][0..@as(usize, x.key_length)];
        const y_key = y_buffer[@as(usize, y.key_offset)..][0..@as(usize, y.key_length)];
        const key_order = std.mem.order(u8, y_key, x_key);
        if (key_order != .eq) return key_order;

        const x_str = x_buffer[@as(usize, x.offset)..][0..@as(usize, x.length)];
        const y_str = y_buffer[@as(usize, y.offset)..][0..@as(usize, y.length)];
        return std.mem.order(u8, y_str, x_str);
    }

    pub fn string(self: Line, buffer: []const u8) []const u8 {
        return buffer[@as(usize, self.offset)..][0..@as(usize, self.length)];
    }
};

pub const LineCmp = *const fn (
    args: *const Args,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order;

pub const LineTable = struct {
    lines: []Line,
    contents: []const u8,
};

test "line: lexicographic_cmp" {
    const raw =
        \\abc
        \\defghij
        \\defghij
        \\
    ;
    const key = Key{ .start = 1, .end = 0 };
    const args = Args{ .keys = &[_]Key{key} };
    const line1 = Line.init(raw[0..3], 0, key, args.separator);
    const line2 = Line.init(raw[5..12], 5, key, args.separator);
    const line3 = Line.init(raw[13..20], 13, key, args.separator);
    try std.testing.expectEqual(.lt, Line.lexicographic_cmp(&args, line1, raw, line2, raw));
    try std.testing.expectEqual(.gt, Line.lexicographic_cmp(&args, line2, raw, line1, raw));
    try std.testing.expectEqual(.eq, Line.lexicographic_cmp(&args, line2, raw, line3, raw));
}

test "line: rlexicographic_cmp" {
    const raw =
        \\abc
        \\defghij
        \\defghij
        \\
    ;
    const key = Key{ .start = 1, .end = 0 };
    const args = Args{ .keys = &[_]Key{key} };
    const line1 = Line.init(raw[0..3], 0, key, args.separator);
    const line2 = Line.init(raw[5..12], 5, key, args.separator);
    const line3 = Line.init(raw[13..20], 13, key, args.separator);
    try std.testing.expectEqual(.gt, Line.rlexicographic_cmp(&args, line1, raw, line2, raw));
    try std.testing.expectEqual(.lt, Line.rlexicographic_cmp(&args, line2, raw, line1, raw));
    try std.testing.expectEqual(.eq, Line.rlexicographic_cmp(&args, line2, raw, line3, raw));
}

test "line: with key (-k 2,2 with -t space)" {
    const raw =
        \\3 cherry 0.1
        \\1 apple  0.3
        \\2 banana 0.2
        \\
    ;
    const key = Key{ .start = 2, .end = 3 }; // parse_key turns -k 2,2 into end exclusive
    const args = Args{ .keys = &[_]Key{key} };
    const line1 = Line.init(raw[0..12], 0, key, args.separator);
    const line2 = Line.init(raw[13..24], 13, key, args.separator);
    const line3 = Line.init(raw[25..37], 25, key, args.separator);
    try std.testing.expectEqualStrings("cherry", raw[line1.key_offset..][0..line1.key_length]);
    try std.testing.expectEqualStrings("apple", raw[line2.key_offset..][0..line2.key_length]);
    try std.testing.expectEqualStrings("banana", raw[line3.key_offset..][0..line3.key_length]);
    try std.testing.expectEqual(.lt, Line.lexicographic_cmp(&args, line2, raw, line3, raw));
    try std.testing.expectEqual(.gt, Line.lexicographic_cmp(&args, line3, raw, line2, raw));
    try std.testing.expectEqual(.eq, Line.lexicographic_cmp(&args, line3, raw, line3, raw));
}

test "line: with key (-k 2,3 with -t ,)" {
    const raw =
        \\3,cherry,0.1,
        \\1,apple,0.3,red
        \\2,banana,0.2,yellow
        \\
    ;
    const key = Key{ .start = 2, .end = 4 };
    const args = Args{ .keys = &[_]Key{key}, .separator = ',' };
    const line1 = Line.init(raw[0..14], 0, key, args.separator);
    const line2 = Line.init(raw[14..30], 14, key, args.separator);
    const line3 = Line.init(raw[30..50], 30, key, args.separator);
    try std.testing.expectEqualStrings("cherry,0.1", raw[line1.key_offset..][0..line1.key_length]);
    try std.testing.expectEqualStrings("apple,0.3", raw[line2.key_offset..][0..line2.key_length]);
    try std.testing.expectEqualStrings("banana,0.2", raw[line3.key_offset..][0..line3.key_length]);
}

test "line: with multiple keys" {
    const raw =
        \\a 1
        \\a 2
        \\b 1
        \\b 2
        \\
    ;
    const keys = &[_]Key{ .{ .start = 1, .end = 1 }, .{ .start = 2, .end = 2 } };
    const args = Args{ .keys = keys, .separator = ' ' };
    const line1 = Line.init(raw[0..3], 0, keys[0], args.separator);
    const line2 = Line.init(raw[4..7], 4, keys[0], args.separator);
    const line3 = Line.init(raw[8..11], 8, keys[0], args.separator);
    const line4 = Line.init(raw[12..15], 12, keys[0], args.separator);
    try std.testing.expectEqual(.lt, Line.lexicographic_cmp(&args, line1, raw, line2, raw));
    try std.testing.expectEqual(.lt, Line.lexicographic_cmp(&args, line1, raw, line3, raw));
    try std.testing.expectEqual(.lt, Line.lexicographic_cmp(&args, line1, raw, line4, raw));
    try std.testing.expectEqual(.lt, Line.lexicographic_cmp(&args, line2, raw, line3, raw));
    try std.testing.expectEqual(.lt, Line.lexicographic_cmp(&args, line2, raw, line4, raw));
    try std.testing.expectEqual(.lt, Line.lexicographic_cmp(&args, line3, raw, line4, raw));
}
