const std = @import("std");

pub const Line = struct {
    offset: u32,
    length: u32,
    prefix: u32,

    pub fn init(raw: []const u8, offset: usize) Line {
        var prefix_bytes: [4]u8 = .{ 0, 0, 0, 0 };
        const n = @min(raw.len, 4);
        @memcpy(prefix_bytes[0..n], raw[0..n]);
        const prefix = std.mem.readInt(u32, &prefix_bytes, .big);

        return .{
            .offset = @intCast(offset),
            .length = @intCast(raw.len),
            .prefix = prefix,
        };
    }

    pub fn size() usize {
        return @sizeOf(Line);
    }

    pub fn cmp(self: Line, other: Line, buffer: []const u8) std.math.Order {
        const by_prefix = std.math.order(self.prefix, other.prefix);
        if (by_prefix != .eq) return by_prefix;

        const self_start = @as(usize, self.offset);
        const self_end = self_start + @as(usize, self.length);
        const other_start = @as(usize, other.offset);
        const other_end = other_start + @as(usize, other.length);
        return std.mem.order(u8, buffer[self_start..self_end], buffer[other_start..other_end]);
    }

    pub fn string(self: Line, buffer: []const u8) []const u8 {
        return buffer[@as(usize, self.offset)..][0..@as(usize, self.length)];
    }
};

pub const LineTable = struct {
    lines: []Line,
    contents: []const u8,
};

test "line" {
    const raw =
        \\abc
        \\defghij
        \\defghij
        \\
    ;
    const line1 = Line.init(raw[0..3], 0);
    const line2 = Line.init(raw[5..12], 5);
    const line3 = Line.init(raw[13..20], 13);
    try std.testing.expectEqual(.lt, line1.cmp(line2, raw));
    try std.testing.expectEqual(.gt, line2.cmp(line1, raw));
    try std.testing.expectEqual(.eq, line2.cmp(line3, raw));
}
