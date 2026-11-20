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
    const Head = struct { line: Line, string: []const u8 };
    const no_run = std.math.maxInt(usize);

    readers: []*File.Reader,
    heads: []Head, // One borrowed record per live run.
    tree: []usize, // Slot 0: winner; [1..p): losers. Leaves are implicit (p = tree.len).
    s: *const Settings,

    fn next_head(self: *Losertree, run_idx: usize) !usize {
        std.debug.assert(run_idx < self.readers.len);
        const string = self.readers[run_idx].interface.takeDelimiterInclusive(
            self.s.delimiter,
        ) catch |err| switch (err) {
            error.EndOfStream => return no_run,
            else => return err,
        };
        // Keep the delimiter for output, but compare the same payload as the in-memory sort.
        const l = Line.init(string[0 .. string.len - 1], 0, self.s.first_key, self.s.separator);
        self.heads[run_idx] = .{ .line = l, .string = string };
        return run_idx;
    }

    fn wins(self: *const Losertree, left: usize, right: usize) bool {
        if (left == no_run) return false;
        if (right == no_run) return true;
        const a = self.heads[left];
        const b = self.heads[right];
        const order = Line.cmp(self.s, a.line, a.string, b.line, b.string);
        return order < 0 or (order == 0 and left < right);
    }

    fn build_tree(self: *Losertree, i: usize) Io.Reader.DelimiterError!usize {
        const p = self.tree.len;
        if (i >= p) {
            const run = i - p;
            return if (run < self.readers.len) self.next_head(run) else no_run;
        }
        const left = try self.build_tree(2 * i);
        const right = try self.build_tree(2 * i + 1);
        if (self.wins(left, right)) {
            self.tree[i] = right;
            return left;
        }
        self.tree[i] = left;
        return right;
    }

    pub fn init(gpa: Allocator, readers: []*File.Reader, s: *const Settings) !Losertree {
        if (readers.len == 0) return error.NoReaders;
        const p = try std.math.ceilPowerOfTwo(usize, readers.len);
        const tree = try gpa.alloc(usize, p);
        errdefer gpa.free(tree);
        const heads = try gpa.alloc(Head, readers.len);
        errdefer gpa.free(heads);
        var l: Losertree = .{ .readers = readers, .heads = heads, .tree = tree, .s = s };
        l.tree[0] = try l.build_tree(1);

        return l;
    }

    pub fn deinit(self: *Losertree, gpa: Allocator) void {
        gpa.free(self.heads);
        gpa.free(self.tree);
    }

    pub fn peek(self: *const Losertree) ?[]const u8 {
        const winner = self.tree[0];
        return if (winner == no_run) null else self.heads[winner].string;
    }

    pub fn advance(self: *Losertree) !void {
        const winner = self.tree[0];
        if (winner == no_run) return;
        var candidate = try self.next_head(winner);
        var i = (self.tree.len + winner) / 2;
        while (i > 0) : (i /= 2) {
            if (self.wins(self.tree[i], candidate)) {
                mem.swap(usize, &self.tree[i], &candidate);
            }
        }
        self.tree[0] = candidate;
    }

    pub fn advance_unique(self: *Losertree, gpa: Allocator) !void {
        const run = self.tree[0];
        if (run == no_run) return;
        const winner = self.heads[run];
        const previous = try gpa.dupe(u8, winner.string);
        defer gpa.free(previous);

        try self.advance();
        while (self.tree[0] != no_run) {
            const next = self.heads[self.tree[0]];
            if (Line.cmp(self.s, winner.line, previous, next.line, next.string) != 0) break;
            try self.advance();
        }
    }
};

test "Losertree: init" {
    const test_gpa = std.testing.allocator;
    const io = std.testing.io;
    const s = Settings{ .tmp_dir = "test_data/tmp" };
    try std.testing.expectError(error.NoReaders, Losertree.init(test_gpa, &.{}, &s));
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

    try std.testing.expectEqual(@as(usize, 4), tree.tree.len);
    const expected_matches = [_][]const u8{ "alligator\n", "apple\n", "apple\n" };
    for (expected_matches, [_]usize{ 0, 2, 1 }, tree.tree[0..3]) |text, run_idx, match| {
        try std.testing.expectEqual(run_idx, match);
        try std.testing.expectEqualStrings(text, tree.heads[match].string);
    }
    try std.testing.expectEqual(Losertree.no_run, tree.tree[3]);

    var previous: [run_buffer_size]u8 = undefined;
    var previous_len: usize = 0;
    var previous_run: usize = 0;
    var counts: [paths.len]usize = @splat(0);
    while (tree.peek()) |text| {
        const run_idx = tree.tree[0];
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

test "Losertree: empty runs and prefix records with a custom delimiter" {
    const test_gpa = std.testing.allocator;
    const runs = [_][]const u8{ "", "a|b|", "|a\x00|b|" };
    var storage: [runs.len]File.Reader = undefined;
    var readers: [runs.len]*File.Reader = undefined;
    for (runs, &storage, &readers) |run, *reader, *slot| {
        reader.* = .{ .io = std.testing.io, .file = File.stdin(), .interface = .fixed(run) };
        slot.* = reader;
    }
    const s = Settings{ .delimiter = '|' };
    var tree = try Losertree.init(test_gpa, &readers, &s);
    defer tree.deinit(test_gpa);

    for ([_][]const u8{ "|", "a|", "a\x00|", "b|", "b|" }) |expected| {
        try std.testing.expectEqualStrings(expected, tree.peek() orelse return error.MissingNode);
        try tree.advance();
    }
    try std.testing.expect(tree.peek() == null);
}

test "Losertree: peek and advance with one reader" {
    const test_gpa = std.testing.allocator;
    const io = std.testing.io;
    const s = Settings{ .tmp_dir = "test_data/tmp" };
    const file = try Dir.cwd().openFile(io, s.tmp_dir ++ "/1.tmp", .{ .mode = .read_only });
    defer file.close(io);

    var buffer: [25]u8 = undefined;
    var reader = file.reader(io, &buffer);
    var readers = [_]*File.Reader{&reader};
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
        try std.testing.expectEqualStrings(text, tree.peek() orelse return error.MissingNode);
        try std.testing.expectEqualStrings(text, tree.peek() orelse return error.MissingNode);
        try tree.advance();
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
