const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const line = @import("line.zig");
const Line = line.Line;
const Settings = @import("settings.zig").Settings;

pub const Losertree = struct {
    const Node = struct { run_idx: usize, line: Line, string: []const u8 };

    readers: []*File.Reader,
    tree: []?Node, // slot 0: overall winner; [1..p): match losers; [p..2*p): run heads
    p: usize, // stores the next power of 2 of readers.len
    s: *const Settings,

    fn next_node(self: *Losertree, run_idx: usize) !?Node {
        std.debug.assert(run_idx < self.readers.len);
        const string = self.readers[run_idx].interface.takeDelimiterInclusive(
            self.s.delimiter,
        ) catch |err| {
            switch (err) {
                error.EndOfStream => return null,
                else => return err,
            }
        };
        const l = Line.init(string, 0, self.s.first_key, self.s.separator);
        return .{ .run_idx = run_idx, .line = l, .string = string };
    }

    fn build_match(self: *Losertree, i: usize, left: ?Node, right: ?Node) ?Node {
        if (left) |a| {
            if (right) |b| {
                const order = Line.cmp(self.s, a.line, a.string, b.line, b.string);
                if (order < 0 or (order == 0 and a.run_idx < b.run_idx)) {
                    self.tree[i] = b;
                    return a;
                }
                self.tree[i] = a;
                return b;
            }
        }

        self.tree[i] = null;
        return if (left != null) left else right;
    }

    const MAX_BUILD_DEPTH = @bitSizeOf(usize) - 2;

    fn build_tree(
        self: *Losertree,
        i: usize,
        depth: usize,
    ) error{MaxRecursionDepthReached}!?Node {
        @branchHint(.cold);
        if (depth > MAX_BUILD_DEPTH) return error.MaxRecursionDepthReached;
        if (i >= self.p) return self.tree[i];

        const left = try self.build_tree(2 * i, depth + 1);
        const right = try self.build_tree(2 * i + 1, depth + 1);
        return self.build_match(i, left, right);
    }

    pub fn init(gpa: Allocator, readers: []*File.Reader, s: *const Settings) !Losertree {
        std.debug.assert(readers.len >= 2);
        const p = try std.math.ceilPowerOfTwo(usize, readers.len);
        const tree_len = try std.math.mul(usize, 2, p);
        const tree = try gpa.alloc(?Node, tree_len);
        errdefer gpa.free(tree);
        @memset(tree, null);
        var l: Losertree = .{ .readers = readers, .tree = tree, .p = p, .s = s };

        for (0..readers.len) |run_idx| {
            tree[p + run_idx] = try l.next_node(run_idx);
        }
        l.tree[0] = try l.build_tree(1, 0);

        return l;
    }

    pub fn deinit(self: *Losertree, gpa: Allocator) void {
        gpa.free(self.tree);
    }

    pub fn peek(self: *Losertree) ?[]const u8 {
        if (self.tree[0]) |n| return n.string;
        return null;
    }

    pub fn advance(self: *Losertree) !void {
        const winner = self.tree[0] orelse return;
        var candidate = try self.next_node(winner.run_idx);
        const leaf = self.p + winner.run_idx;
        self.tree[leaf] = candidate;

        var i = leaf / 2;
        while (i > 0) : (i /= 2) {
            candidate = self.build_match(i, candidate, self.tree[i]);
        }
        self.tree[0] = candidate;
    }

    pub fn advance_unique(self: *Losertree, gpa: Allocator) !void {
        const winner = self.tree[0] orelse return;
        const previous = try gpa.dupe(u8, winner.string);
        defer gpa.free(previous);

        try self.advance();
        while (self.tree[0]) |next| {
            if (Line.cmp(self.s, winner.line, previous, next.line, next.string) != 0) break;
            try self.advance();
        }
    }
};

test "Losertree: init" {
    const test_gpa = std.testing.allocator;
    const io = std.testing.io;
    const s = Settings{ .tmp_dir = "test_data/tmp" };
    const paths = [_][]const u8{
        s.tmp_dir ++ "/0.tmp",
        s.tmp_dir ++ "/1.tmp",
        s.tmp_dir ++ "/1.tmp",
    };
    var files: [paths.len]File = undefined;
    var open_files: usize = 0;
    defer for (files[0..open_files]) |file| file.close(io);

    var buffer: [75]u8 = undefined;
    const run_buffer_size = buffer.len / paths.len;
    var reader_storage: [paths.len]File.Reader = undefined;
    var readers: [paths.len]*File.Reader = undefined;
    for (paths, 0..) |path, i| {
        files[i] = try Dir.cwd().openFile(io, path, .{ .mode = .read_only });
        open_files += 1;
        reader_storage[i] = files[i].reader(
            io,
            buffer[i * run_buffer_size .. (i + 1) * run_buffer_size],
        );
        readers[i] = &reader_storage[i];
    }

    var tree = try Losertree.init(test_gpa, &readers, &s);
    defer tree.deinit(test_gpa);

    try std.testing.expectEqual(@as(usize, 4), tree.p);
    try std.testing.expectEqual(@as(usize, 8), tree.tree.len);
    const expected_matches = [_][]const u8{ "alligator\n", "apple\n", "apple\n" };
    for (expected_matches, [_]usize{ 0, 2, 1 }, tree.tree[0..3]) |text, run_idx, match| {
        const node = match orelse return error.MissingNode;
        try std.testing.expectEqual(run_idx, node.run_idx);
        try std.testing.expectEqualStrings(text, node.string);
    }
    try std.testing.expect(tree.tree[3] == null);
    try std.testing.expect(tree.tree[7] == null);

    var previous: [run_buffer_size]u8 = undefined;
    var previous_len: usize = 0;
    var previous_run: usize = 0;
    var counts: [paths.len]usize = @splat(0);
    while (tree.peek()) |text| {
        const run_idx = tree.tree[0].?.run_idx;
        switch (mem.order(u8, previous[0..previous_len], text)) {
            .lt => {},
            .eq => try std.testing.expect(previous_run <= run_idx),
            .gt => return error.OutOfOrder,
        }
        @memcpy(previous[0..text.len], text);
        previous_len = text.len;
        previous_run = run_idx;
        counts[run_idx] += 1;
        try tree.advance();
    }
    try std.testing.expectEqual([_]usize{ 22, 12, 12 }, counts);
    try tree.advance();
    try std.testing.expect(tree.peek() == null);
}

test "Losertree: peek does not advance either reader" {
    const test_gpa = std.testing.allocator;
    const io = std.testing.io;
    const s = Settings{ .tmp_dir = "test_data/tmp" };
    const file = try Dir.cwd().openFile(io, s.tmp_dir ++ "/1.tmp", .{ .mode = .read_only });
    defer file.close(io);

    var first_buffer: [25]u8 = undefined;
    var second_buffer: [25]u8 = undefined;
    var first_reader = file.reader(io, &first_buffer);
    var second_reader = file.reader(io, &second_buffer);
    var readers = [_]*File.Reader{ &first_reader, &second_reader };
    var tree = try Losertree.init(test_gpa, &readers, &s);
    defer tree.deinit(test_gpa);

    const expected = [_][]const u8{
        "apple\n",
        "banana\n",
        "blackberry\n",
        "blueberry\n",
        "cherry\n",
        "grape\n",
        "orange\n",
        "pear\n",
        "pineapple\n",
        "raspberry\n",
        "strawberry\n",
        "watermelon\n",
    };
    for (expected) |text| {
        for (0..readers.len) |run_idx| {
            try std.testing.expectEqualStrings(text, tree.peek() orelse return error.MissingNode);
            try std.testing.expectEqualStrings(text, tree.peek() orelse return error.MissingNode);
            try std.testing.expectEqual(run_idx, tree.tree[0].?.run_idx);
            try tree.advance();
        }
    }
    try std.testing.expect(tree.peek() == null);
    try tree.advance();
    try std.testing.expect(tree.peek() == null);
}

test "Losertree: advance_unique skips equal keys across reader refills" {
    const test_gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "a", .data = "1 first\n1 again\n3 third\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "b", .data = "1 other\n2 second\n3 final\n" });

    const a = try tmp.dir.openFile(io, "a", .{ .mode = .read_only });
    defer a.close(io);
    const b = try tmp.dir.openFile(io, "b", .{ .mode = .read_only });
    defer b.close(io);
    var a_buffer: [9]u8 = undefined;
    var b_buffer: [9]u8 = undefined;
    var a_reader = a.reader(io, &a_buffer);
    var b_reader = b.reader(io, &b_buffer);
    var readers = [_]*File.Reader{ &a_reader, &b_reader };

    const s = Settings{ .unique = true, .first_key = .{ .pos = 0 }, .keys = &.{.{ .pos = 0 }} };
    var tree = try Losertree.init(test_gpa, &readers, &s);
    defer tree.deinit(test_gpa);

    for ([_][]const u8{ "1 first\n", "2 second\n", "3 third\n" }) |text| {
        try std.testing.expectEqualStrings(text, tree.peek() orelse return error.MissingNode);
        try tree.advance_unique(test_gpa);
    }
    try std.testing.expect(tree.peek() == null);
    try tree.advance_unique(test_gpa);
    try std.testing.expect(tree.peek() == null);
}
