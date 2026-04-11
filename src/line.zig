const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const settings = @import("settings.zig");
const Settings = settings.Settings;
const CmpType = settings.CmpType;
const Key = settings.Key;
const simd = @import("simd.zig");
const lib_cmp = @import("cmp.zig");

pub const KeySlice = struct {
    offset: u32,
    length: u32,

    const GetKeyRes = struct { offset: usize, length: usize };

    inline fn simd_get(raw: []const u8, key: Key, separator: u8) GetKeyRes {
        var offset: usize = 0;
        var seen: usize = 0;
        const sep: simd.VecU8 = @splat(separator);
        var i: usize = 0;
        const max_i = raw.len -| simd.VEC_LEN;

        while (i < max_i) : (i += simd.VEC_LEN) {
            const bytes: simd.VecU8 = raw[i .. i + simd.VEC_LEN][0..simd.VEC_LEN].*;
            var mask: std.meta.Int(.unsigned, simd.VEC_LEN) = @bitCast(bytes == sep);
            while (mask != 0) {
                seen += 1;
                if (seen == key.pos) {
                    offset = i + @ctz(mask) + 1;
                } else if (seen == key.pos + 1) {
                    return .{ .offset = offset, .length = i + @ctz(mask) - offset };
                }
                mask &= mask - 1;
            }
        }

        while (i < raw.len and seen < key.pos + 1) : (i += 1) {
            if (raw[i] == separator) {
                seen += 1;
                if (seen == key.pos) {
                    offset = i + 1;
                } else if (seen == key.pos + 1) {
                    return .{ .offset = offset, .length = i - offset };
                }
            }
        }
        if (offset == 0) {
            @branchHint(.cold);
            return .{ .offset = 0, .length = 0 };
        }
        return .{ .offset = offset, .length = raw.len - offset };
    }

    inline fn get_consecutive(raw: []const u8, key: Key) GetKeyRes {
        var offset: usize = 0;
        var seen: usize = 0;
        var i: usize = 0;

        while (i < raw.len and seen < key.pos + 1) : (i += 1) {
            if (ascii.isWhitespace(raw[i])) {
                seen += 1;
                if (seen == key.pos) {
                    i += 1;
                    while (i < raw.len and ascii.isWhitespace(raw[i])) : (i += 1) {}
                    offset = i;
                } else if (seen == key.pos + 1) {
                    return .{ .offset = offset, .length = i - offset };
                } else {
                    i += 1;
                    while (i < raw.len and ascii.isWhitespace(raw[i])) : (i += 1) {}
                }
            }
        }
        if (offset == 0) {
            @branchHint(.cold);
            return .{ .offset = 0, .length = 0 };
        }
        return .{ .offset = offset, .length = raw.len - offset };
    }

    pub fn init(raw: []const u8, key: ?Key, separator: u8) KeySlice {
        var offset: usize = 0;
        var length: usize = raw.len;
        if (key) |k| {
            const res = if (ascii.isWhitespace(separator))
                get_consecutive(raw, k)
            else
                simd_get(raw, k, separator);
            offset = res.offset;
            length = res.length;
        }
        return .{ .offset = @intCast(offset), .length = @intCast(length) };
    }

    pub inline fn string(self: KeySlice, buf: []const u8) []const u8 {
        return buf[@as(usize, self.offset) .. self.length + self.offset];
    }
};

pub const Line = struct {
    offset: u32,
    length: u32,
    key_slice: KeySlice,

    pub fn init(raw: []const u8, offset: usize, key: ?Key, separator: u8) Line {
        const key_slice = KeySlice.init(raw, key, separator);
        return .{
            .offset = @intCast(offset),
            .length = @intCast(raw.len),
            .key_slice = key_slice,
        };
    }

    pub inline fn size() usize {
        return @sizeOf(Line);
    }

    pub inline fn string(self: Line, buffer: []const u8) []const u8 {
        return buffer[@as(usize, self.offset)..][0..@as(usize, self.length)];
    }

    inline fn cmp_inner(
        reverse: i8,
        cmp_type: CmpType,
        a: KeySlice,
        a_buf: []const u8,
        b: KeySlice,
        b_buf: []const u8,
    ) i8 {
        const ord = switch (cmp_type) {
            .lexicographic => lib_cmp.lexicographic(a.string(a_buf), b.string(b_buf)),
            .numeric => lib_cmp.numeric(a.string(a_buf), b.string(b_buf)),
        };
        return ord * reverse;
    }

    pub fn cmp(s: *const Settings, a: Line, a_buf: []const u8, b: Line, b_buf: []const u8) i8 {
        const a_str = a.string(a_buf);
        const b_str = b.string(b_buf);

        var ord: i8 = 0;
        if (s.keys) |keys| {
            ord = cmp_inner(
                keys[0].reverse,
                keys[0].cmp_type,
                a.key_slice,
                a_str,
                b.key_slice,
                b_str,
            );
            if (ord != 0) return ord * s.reverse;
            for (keys[1..]) |key| {
                const a_key = KeySlice.init(a_str, key, s.separator);
                const b_key = KeySlice.init(b_str, key, s.separator);
                ord = cmp_inner(
                    key.reverse,
                    key.cmp_type,
                    a_key,
                    a_str,
                    b_key,
                    b_str,
                );
                if (ord != 0) return ord * s.reverse;
            }
            if (!s.unique and ord == 0) {
                switch (mem.order(u8, a_str, b_str)) {
                    .lt => ord = -1,
                    .gt => ord = 1,
                    .eq => ord = 0,
                }
            }
        } else {
            ord = cmp_inner(1, s.cmp_type, a.key_slice, a_str, b.key_slice, b_str);
        }
        return ord * s.reverse;
    }
};

pub const LineTable = struct {
    lines: []Line,
    contents: []const u8,
};

test "line: init without key" {
    const raw = "cherry,0.1,,2";
    const line = Line.init(raw, 0, null, ',');
    const expected = Line{
        .offset = 0,
        .length = 13,
        .key_slice = .{ .offset = 0, .length = 13 },
    };
    try std.testing.expectEqual(expected, line);
    try std.testing.expectEqualStrings(expected.string(raw), raw);

    const short_raw = "ab";
    const short_line = Line.init(short_raw, 0, null, ',');
    const short_expected = Line{
        .offset = 0,
        .length = 2,
        .key_slice = .{ .offset = 0, .length = 2 },
    };
    try std.testing.expectEqual(short_expected, short_line);
    try std.testing.expectEqualStrings(short_expected.string(short_raw), short_raw);
}

test "line: init with simd invocation" {
    const raw = "apple,banana,cherry,date,elderberry,fig,grape,lemon";
    const line0 = Line.init(raw, 0, .{ .pos = 0 }, ',');
    const expected0 = Line{
        .offset = 0,
        .length = raw.len,
        .key_slice = .{ .offset = 0, .length = 5 },
    };
    try std.testing.expectEqual(expected0, line0);

    const line2 = Line.init(raw, 0, .{ .pos = 2 }, ',');
    const expected2 = Line{
        .offset = 0,
        .length = raw.len,
        .key_slice = .{ .offset = 13, .length = 6 },
    };
    try std.testing.expectEqual(expected2, line2);

    const line6 = Line.init(raw, 0, .{ .pos = 6 }, ',');
    const expected6 = Line{
        .offset = 0,
        .length = raw.len,
        .key_slice = .{ .offset = 40, .length = 5 },
    };
    try std.testing.expectEqual(expected6, line6);

    const line7 = Line.init(raw, 0, .{ .pos = 7 }, ',');
    const expected7 = Line{
        .offset = 0,
        .length = raw.len,
        .key_slice = .{ .offset = 46, .length = 5 },
    };
    try std.testing.expectEqual(expected7, line7);

    const line_out_of_bounds = Line.init(raw, 0, .{ .pos = 10000 }, ',');
    const expected_out_of_bounds = Line{
        .offset = 0,
        .length = raw.len,
        .key_slice = .{ .offset = 0, .length = 0 },
    };
    try std.testing.expectEqual(expected_out_of_bounds, line_out_of_bounds);
}

test "line: with key" {
    const raw = "cherry,0.1,,2";
    const line0 = Line.init(raw, 0, .{ .pos = 0 }, ',');
    const expected0 = Line{
        .offset = 0,
        .length = 13,
        .key_slice = .{ .offset = 0, .length = 6 },
    };
    try std.testing.expectEqual(expected0, line0);

    const line1 = Line.init(raw, 0, .{ .pos = 1 }, ',');
    const expected1 = Line{
        .offset = 0,
        .length = 13,
        .key_slice = .{ .offset = 7, .length = 3 },
    };
    try std.testing.expectEqual(expected1, line1);

    const empty_line = Line.init(raw, 0, .{ .pos = 2 }, ',');
    const expected_empty_line = Line{
        .offset = 0,
        .length = 13,
        .key_slice = .{ .offset = 11, .length = 0 },
    };
    try std.testing.expectEqual(expected_empty_line, empty_line);
}

test "line: init with consecutive delimiters" {
    const raw = "apple  banana cherry    date fig";
    const line0 = Line.init(raw, 0, .{ .pos = 0 }, ' ');
    const expected0 = Line{
        .offset = 0,
        .length = raw.len,
        .key_slice = .{ .offset = 0, .length = 5 },
    };
    try std.testing.expectEqual(expected0, line0);

    const line1 = Line.init(raw, 0, .{ .pos = 1 }, ' ');
    const expected1 = Line{
        .offset = 0,
        .length = raw.len,
        .key_slice = .{ .offset = 7, .length = 6 },
    };
    try std.testing.expectEqual(expected1, line1);

    const line3 = Line.init(raw, 0, .{ .pos = 3 }, ' ');
    const expected3 = Line{
        .offset = 0,
        .length = raw.len,
        .key_slice = .{ .offset = 24, .length = 4 },
    };
    try std.testing.expectEqual(expected3, line3);
}
