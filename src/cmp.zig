const std = @import("std");

const Args = @import("argparse.zig").Args;
const line = @import("line.zig");
const Key = line.Key;
const Line = line.Line;

const CmpType = enum {
    lexicographic_cache_key,
    lexicographic_key,
    lexicographic_string,
    reverse_lexicographic_cache_key,
    reverse_lexicographic_key,
    reverse_lexicographic_string,
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
                .lexicographic_cache_key => lexicographic_cmp_cache_key,
                .lexicographic_key => lexicographic_cmp_key,
                .lexicographic_string => lexicographic_cmp_string,
                .reverse_lexicographic_cache_key => rlexicographic_cmp_cache_key,
                .reverse_lexicographic_key => rlexicographic_cmp_key,
                .reverse_lexicographic_string => rlexicographic_cmp_string,
            },
        };
    }

    pub fn set_reverse(self: *LineCmp) void {
        switch (self.cmp_type) {
            .lexicographic_cache_key => {
                self.cmp_type = .reverse_lexicographic_cache_key;
                self.cmp_fn = rlexicographic_cmp_cache_key;
            },
            .lexicographic_key => {
                self.cmp_type = .reverse_lexicographic_key;
                self.cmp_fn = rlexicographic_cmp_key;
            },
            .lexicographic_string => {
                self.cmp_type = .reverse_lexicographic_string;
                self.cmp_fn = rlexicographic_cmp_string;
            },
            .reverse_lexicographic_cache_key => {
                self.cmp_type = .lexicographic_cache_key;
                self.cmp_fn = lexicographic_cmp_cache_key;
            },
            .reverse_lexicographic_key => {
                self.cmp_type = .lexicographic_key;
                self.cmp_fn = lexicographic_cmp_key;
            },
            .reverse_lexicographic_string => {
                self.cmp_type = .lexicographic_string;
                self.cmp_fn = lexicographic_cmp_string;
            },
        }
    }
};

pub fn lexicographic_cmp_cache_key(
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

pub fn rlexicographic_cmp_cache_key(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    return lexicographic_cmp_cache_key(key, separator, y, y_buffer, x, x_buffer);
}

pub fn lexicographic_cmp_key(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    const x_str = Line.string(x, x_buffer);
    const y_str = Line.string(y, y_buffer);
    const x_key_info = Line.get_key(x_str, key, separator);
    const y_key_info = Line.get_key(y_str, key, separator);
    const x_key = x_str[@as(usize, x_key_info.offset)..][0..@as(usize, x_key_info.length)];
    const y_key = y_str[@as(usize, y_key_info.offset)..][0..@as(usize, y_key_info.length)];
    return std.mem.order(u8, x_key, y_key);
}

pub fn rlexicographic_cmp_key(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    return lexicographic_cmp_key(key, separator, y, y_buffer, x, x_buffer);
}

pub fn lexicographic_cmp_string(
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

pub fn rlexicographic_cmp_string(
    key: Key,
    separator: u8,
    x: Line,
    x_buffer: []const u8,
    y: Line,
    y_buffer: []const u8,
) std.math.Order {
    return lexicographic_cmp_string(key, separator, y, y_buffer, x, x_buffer);
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
