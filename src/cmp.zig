const std = @import("std");

const Args = @import("argparse.zig").Args;
const line = @import("line.zig");
const Key = line.Key;
const Line = line.Line;

const Number = struct {
    sign: i8,
    int_start: u32,
    int_length: u32,
    frac_start: u32,
    frac_length: u32,

    pub fn get_number(str: []const u8) Number {
        var i: usize = 0;
        while (i < str.len and std.ascii.isWhitespace(str[i])) : (i += 1) {}
        var sign: i8 = 1;
        if (i < str.len) {
            if (str[i] == '-') {
                sign = -1;
                i += 1;
            } else if (str[i] == '+') i += 1;
        }

        var int_start = i;
        while (i < str.len and std.ascii.isDigit(str[i])) : (i += 1) {}
        const int_end = i;
        while (int_start < int_end and str[int_start] == '0') : (int_start += 1) {}
        const int_length = int_end - int_start;

        var frac_start: usize = i;
        var frac_length: usize = 0;

        if (i < str.len and str[i] == '.') {
            i += 1;
            frac_start = i;

            while (i < str.len and std.ascii.isDigit(str[i])) : (i += 1) {}
            frac_length = i - frac_start;
        }

        return .{
            .sign = sign,
            .int_start = @intCast(int_start),
            .int_length = @intCast(int_length),
            .frac_start = @intCast(frac_start),
            .frac_length = @intCast(frac_length),
        };
    }

    pub fn cmp(x: Number, x_str: []const u8, y: Number, y_str: []const u8) std.math.Order {
        if (x.sign != y.sign) return std.math.order(x.sign, y.sign);
        if (x.int_length != y.int_length) return std.math.order(x.int_length, y.int_length);

        const x_int = x_str[@as(usize, x.int_start)..][0..@as(usize, x.int_length)];
        const y_int = y_str[@as(usize, y.int_start)..][0..@as(usize, y.int_length)];
        const int_order = std.mem.order(u8, x_int, y_int);
        if (int_order != .eq) return int_order;

        const x_frac = x_str[@as(usize, x.frac_start)..][0..@as(usize, x.frac_length)];
        const y_frac = y_str[@as(usize, y.frac_start)..][0..@as(usize, y.frac_length)];
        const n = @min(x_frac.len, y_frac.len);
        const prefix_order = std.mem.order(u8, x_frac[0..n], y_frac[0..n]);
        if (prefix_order != .eq) return prefix_order;
        if (x_frac.len == y_frac.len) return std.mem.order(u8, x_str, y_str);

        const longer_frac = if (x_frac.len > y_frac.len) x_frac else y_frac;
        const remainder = longer_frac[n..];

        for (remainder) |c| {
            if (c != '0') {
                return if (x_str.len > y_str.len) .gt else .lt;
            }
        }
        return std.mem.order(u8, x_str, y_str);
    }
};

pub const CmpType = enum {
    lexicographic_cache,
    lexicographic,
    lexicographic_full,
    reverse_lexicographic_cache,
    reverse_lexicographic,
    reverse_lexicographic_full,
    numeric_cache,
    reverse_numeric_cache,
    numeric,
    reverse_numeric,
};

pub const LineCmp = struct {
    cmp_type: CmpType,
    key_idx: usize,
    cmp_fn: *const fn (
        key: Key,
        separator: u8,
        x: Line,
        x_buffer: []const u8,
        y: Line,
        y_buffer: []const u8,
    ) std.math.Order,

    pub fn init(cmp_type: CmpType, key_idx: usize) LineCmp {
        return .{
            .cmp_type = cmp_type,
            .key_idx = key_idx,
            .cmp_fn = switch (cmp_type) {
                .lexicographic_cache => lexicographic_cache_cmp,
                .lexicographic => lexicographic_cmp,
                .lexicographic_full => lexicographic_full_cmp,
                .reverse_lexicographic_cache => rlexicographic_cache_cmp,
                .reverse_lexicographic => rlexicographic_cmp,
                .reverse_lexicographic_full => rlexicographic_full_cmp,
                .numeric_cache => numeric_cache_cmp,
                .numeric => numeric_cmp,
                .reverse_numeric_cache => rnumeric_cache_cmp,
                .reverse_numeric => rnumeric_cmp,
            },
        };
    }

    pub fn set_reverse(self: *LineCmp) void {
        switch (self.cmp_type) {
            .lexicographic_cache => {
                self.cmp_type = .reverse_lexicographic_cache;
                self.cmp_fn = rlexicographic_cache_cmp;
            },
            .lexicographic => {
                self.cmp_type = .reverse_lexicographic;
                self.cmp_fn = rlexicographic_cmp;
            },
            .lexicographic_full => {
                self.cmp_type = .reverse_lexicographic_full;
                self.cmp_fn = rlexicographic_full_cmp;
            },
            .reverse_lexicographic_cache => {
                self.cmp_type = .lexicographic_cache;
                self.cmp_fn = lexicographic_cache_cmp;
            },
            .reverse_lexicographic => {
                self.cmp_type = .lexicographic;
                self.cmp_fn = lexicographic_cmp;
            },
            .reverse_lexicographic_full => {
                self.cmp_type = .lexicographic_full;
                self.cmp_fn = lexicographic_full_cmp;
            },
            .numeric_cache => {
                self.cmp_type = .reverse_numeric_cache;
                self.cmp_fn = rnumeric_cache_cmp;
            },
            .reverse_numeric_cache => {
                self.cmp_type = .numeric_cache;
                self.cmp_fn = numeric_cache_cmp;
            },
            .numeric => {
                self.cmp_type = .reverse_numeric;
                self.cmp_fn = rnumeric_cmp;
            },
            .reverse_numeric => {
                self.cmp_type = .numeric;
                self.cmp_fn = numeric_cmp;
            },
        }
    }
};

pub fn lexicographic_cache_cmp(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    _ = key;
    _ = separator;
    const by_prefix = std.math.order(x.key_prefix, y.key_prefix);
    if (by_prefix != .eq) return by_prefix;
    const x_key = x_buffer[@as(usize, x.key_offset)..][0..@as(usize, x.key_length)];
    const y_key = y_buffer[@as(usize, y.key_offset)..][0..@as(usize, y.key_length)];
    return std.mem.order(u8, x_key, y_key);
}

pub fn rlexicographic_cache_cmp(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    return lexicographic_cache_cmp(key, separator, y, y_buffer, x, x_buffer);
}

pub fn lexicographic_cmp(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    const x_str = x.string(x_buffer);
    const y_str = y.string(y_buffer);
    var x_start = Line.get_key_start_offset(x_str, key, separator);
    var y_start = Line.get_key_start_offset(y_str, key, separator);
    var x_field = key.start;
    var y_field = key.start;

    const n = @min(x_str.len, y_str.len);
    const field_end = if (key.end == 0) n else key.end;
    while (x_start < x_str.len and y_start < y_str.len and (x_field < field_end or y_field < field_end)) : ({
        x_start += 1;
        y_start += 1;
    }) {
        x_field += @as(usize, @intFromBool(x_str[x_start] == separator));
        y_field += @as(usize, @intFromBool(y_str[y_start] == separator));
        if (x_str[x_start] > y_str[y_start]) {
            return .gt;
        } else if (x_str[x_start] < y_str[y_start]) {
            return .lt;
        }
    }
    return std.math.order(x_field, y_field);
}

pub fn rlexicographic_cmp(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    return lexicographic_cmp(key, separator, y, y_buffer, x, x_buffer);
}

pub fn lexicographic_full_cmp(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    _ = key;
    _ = separator;
    const x_str = x_buffer[@as(usize, x.offset)..][0..@as(usize, x.length)];
    const y_str = y_buffer[@as(usize, y.offset)..][0..@as(usize, y.length)];
    return std.mem.order(u8, x_str, y_str);
}

pub fn rlexicographic_full_cmp(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    return lexicographic_full_cmp(key, separator, y, y_buffer, x, x_buffer);
}

pub fn numeric_cache_cmp(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    _ = key;
    _ = separator;
    const x_key = x_buffer[@as(usize, x.key_offset)..][0..@as(usize, x.key_length)];
    const y_key = y_buffer[@as(usize, y.key_offset)..][0..@as(usize, y.key_length)];
    const x_number = Number.get_number(x_key);
    const y_number = Number.get_number(y_key);
    return Number.cmp(x_number, x_key, y_number, y_key);
}

pub fn rnumeric_cache_cmp(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    return numeric_cache_cmp(key, separator, y, y_buffer, x, x_buffer);
}

pub fn numeric_cmp(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    const x_str = x.string(x_buffer);
    const y_str = y.string(y_buffer);
    const x_key_info = Line.get_key(x_str, key, separator);
    const y_key_info = Line.get_key(y_str, key, separator);
    const x_key = x_str[@as(usize, x_key_info.offset)..][0..@as(usize, x_key_info.length)];
    const y_key = y_str[@as(usize, y_key_info.offset)..][0..@as(usize, y_key_info.length)];
    const x_number = Number.get_number(x_key);
    const y_number = Number.get_number(y_key);
    return Number.cmp(x_number, x_key, y_number, y_key);
}

pub fn rnumeric_cmp(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    return numeric_cmp(key, separator, y, y_buffer, x, x_buffer);
}

pub fn cmp(
    args: *const Args,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    for (args.cmp_functions) |fx| {
        const key = args.keys[fx.key_idx];
        const key_order = fx.cmp_fn(key, args.separator, x, x_buffer, y, y_buffer);
        if (key_order != .eq) return key_order;
    }
    return .eq;
}

test "cmp: lexicographic" {
    const test_gpa = std.testing.allocator;
    const raw =
        \\abc
        \\defghij
        \\defghij
        \\
    ;
    const key = Key{ .start = 1, .end = 0 };
    var args = Args{ .keys = &[_]Key{key} };
    try args.build_cmp_functions(test_gpa);
    defer test_gpa.free(args.cmp_functions);
    const line1 = Line.init(raw[0..4], 0, key, args.separator);
    const line2 = Line.init(raw[4..12], 4, key, args.separator);
    const line3 = Line.init(raw[12..20], 12, key, args.separator);
    try std.testing.expectEqual(.lt, cmp(&args, line1, raw, line2, raw));
    try std.testing.expectEqual(.gt, cmp(&args, line2, raw, line1, raw));
    try std.testing.expectEqual(.eq, cmp(&args, line2, raw, line3, raw));
}

test "cmp: reverse lexicographic" {
    const test_gpa = std.testing.allocator;
    const raw =
        \\abc
        \\defghij
        \\defghij
        \\
    ;
    const key = Key{ .start = 1, .end = 0 };
    var args = Args{ .keys = &[_]Key{key}, .reverse = true };
    try args.build_cmp_functions(test_gpa);
    defer test_gpa.free(args.cmp_functions);
    const line1 = Line.init(raw[0..4], 0, key, args.separator);
    const line2 = Line.init(raw[4..12], 4, key, args.separator);
    const line3 = Line.init(raw[12..20], 12, key, args.separator);
    try std.testing.expectEqual(.gt, cmp(&args, line1, raw, line2, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line2, raw, line1, raw));
    try std.testing.expectEqual(.eq, cmp(&args, line2, raw, line3, raw));
}

test "cmp: numeric" {
    const test_gpa = std.testing.allocator;
    const raw =
        \\0.1
        \\  0.1
        \\1
        \\1.0
        \\02
        \\2
        \\
    ;
    const key = Key{ .start = 1, .end = 0 };
    var args = Args{ .keys = &[_]Key{key}, .numeric = true };
    try args.build_cmp_functions(test_gpa);
    defer test_gpa.free(args.cmp_functions);
    const line1 = Line.init(raw[0..4], 0, key, args.separator);
    const line2 = Line.init(raw[4..10], 4, key, args.separator);
    const line3 = Line.init(raw[10..12], 10, key, args.separator);
    const line4 = Line.init(raw[12..16], 12, key, args.separator);
    const line5 = Line.init(raw[16..19], 16, key, args.separator);
    const line6 = Line.init(raw[19..21], 19, key, args.separator);
    try std.testing.expectEqual(.gt, cmp(&args, line1, raw, line2, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line1, raw, line3, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line1, raw, line4, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line1, raw, line5, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line2, raw, line3, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line2, raw, line4, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line2, raw, line5, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line3, raw, line4, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line3, raw, line5, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line4, raw, line5, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line5, raw, line6, raw));
}

test "cmp: with key (-k 2,2 with -t space)" {
    const test_gpa = std.testing.allocator;
    const raw =
        \\3 cherry 0.1
        \\1 apple  0.3
        \\2 banana 0.2
        \\
    ;
    const key = Key{ .start = 2, .end = 3 };
    var args = Args{ .keys = &[_]Key{key} };
    try args.build_cmp_functions(test_gpa);
    defer test_gpa.free(args.cmp_functions);
    const line1 = Line.init(raw[0..13], 0, key, args.separator);
    const line2 = Line.init(raw[13..26], 13, key, args.separator);
    const line3 = Line.init(raw[26..40], 26, key, args.separator);
    try std.testing.expectEqualStrings("cherry", raw[line1.key_offset..][0..line1.key_length]);
    try std.testing.expectEqualStrings("apple", raw[line2.key_offset..][0..line2.key_length]);
    try std.testing.expectEqualStrings("banana", raw[line3.key_offset..][0..line3.key_length]);
    try std.testing.expectEqual(.gt, cmp(&args, line1, raw, line2, raw));
    try std.testing.expectEqual(.gt, cmp(&args, line1, raw, line3, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line2, raw, line3, raw));
}

test "cmp: with multiple keys" {
    const test_gpa = std.testing.allocator;
    const raw =
        \\a 1
        \\a 2
        \\b 1
        \\b 2
        \\
    ;
    const keys = &[_]Key{ .{ .start = 1, .end = 2 }, .{ .start = 2, .end = 3 } };
    var args = Args{ .keys = keys, .separator = ' ' };
    try args.build_cmp_functions(test_gpa);
    defer test_gpa.free(args.cmp_functions);
    const line1 = Line.init(raw[0..4], 0, keys[0], args.separator);
    const line2 = Line.init(raw[4..8], 4, keys[0], args.separator);
    const line3 = Line.init(raw[8..12], 8, keys[0], args.separator);
    const line4 = Line.init(raw[12..16], 12, keys[0], args.separator);
    try std.testing.expectEqual(.lt, cmp(&args, line1, raw, line2, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line1, raw, line3, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line1, raw, line4, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line2, raw, line3, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line2, raw, line4, raw));
    try std.testing.expectEqual(.lt, cmp(&args, line3, raw, line4, raw));
}
