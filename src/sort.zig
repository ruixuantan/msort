const std = @import("std");
const line = @import("line.zig");
const Settings = @import("settings.zig").Settings;
const LineTable = line.LineTable;
const Line = line.Line;

pub fn insertsort(line_table: LineTable, s: *const Settings) void {
    if (line_table.lines.len < 2) {
        @branchHint(.cold);
        return;
    }

    var i: usize = 1;
    while (i < line_table.lines.len) : (i += 1) {
        const key = line_table.lines[i];
        var j = i;
        while (j > 0 and Line.cmp(
            s,
            line_table.lines[j - 1],
            line_table.contents,
            key,
            line_table.contents,
        ) > 0) {
            line_table.lines[j] = line_table.lines[j - 1];
            j -= 1;
        }
        line_table.lines[j] = key;
    }
}

const SORT_THRESHOLD: usize = 16;

fn merge(
    line_table: LineTable,
    tmp_lines: *std.ArrayList(Line),
    mid: usize,
    s: *const Settings,
) void {
    std.debug.assert(mid <= line_table.lines.len);
    if (Line.cmp(
        s,
        line_table.lines[mid - 1],
        line_table.contents,
        line_table.lines[mid],
        line_table.contents,
    ) < 1) return;

    var i: usize = 0;
    var j: usize = mid;
    while (i < mid and j < line_table.lines.len) {
        if (Line.cmp(
            s,
            line_table.lines[i],
            line_table.contents,
            line_table.lines[j],
            line_table.contents,
        ) < 1) {
            tmp_lines.appendAssumeCapacity(line_table.lines[i]);
            i += 1;
        } else {
            tmp_lines.appendAssumeCapacity(line_table.lines[j]);
            j += 1;
        }
    }
    while (i < mid) : (i += 1) {
        tmp_lines.appendAssumeCapacity(line_table.lines[i]);
    }
    while (j < line_table.lines.len) : (j += 1) {
        tmp_lines.appendAssumeCapacity(line_table.lines[j]);
    }
    @memcpy(line_table.lines, tmp_lines.items);
}

pub fn mergesort(gpa: std.mem.Allocator, line_table: LineTable, s: *const Settings) !void {
    // bottom up variant
    {
        var i: usize = 0;
        while (i < line_table.lines.len) : (i += SORT_THRESHOLD) {
            const end = @min(i + SORT_THRESHOLD, line_table.lines.len);
            insertsort(.{
                .lines = line_table.lines[i..end],
                .contents = line_table.contents,
            }, s);
        }
    }

    var size = SORT_THRESHOLD;
    var tmp_lines = try std.ArrayList(Line).initCapacity(gpa, line_table.lines.len);
    defer tmp_lines.deinit(gpa);
    while (size < line_table.lines.len) : (size *= 2) {
        var i: usize = 0;
        while (i < line_table.lines.len) : (i += size * 2) {
            const end = @min(i + size * 2, line_table.lines.len);
            const seg = line_table.lines[i..end];
            if (seg.len <= size) continue;
            merge(.{ .lines = seg, .contents = line_table.contents }, &tmp_lines, size, s);
            tmp_lines.clearRetainingCapacity();
        }
    }
}

fn median_of_3(line_table: LineTable, s: *const Settings) Line {
    const mid = line_table.lines.len >> 1;
    var tmp: [3]Line = .{
        line_table.lines[0],
        line_table.lines[mid],
        line_table.lines[line_table.lines.len - 1],
    };
    const contents = line_table.contents;
    insertsort(.{ .lines = &tmp, .contents = contents }, s);
    return tmp[1];
}

const MAX_ITERATIONS: usize = 10000;

pub fn quicksort(
    line_table: LineTable,
    s: *const Settings,
    iteration: usize,
) error{MaxIterationsReached}!void {
    // hoare partitioning variant
    if (iteration >= MAX_ITERATIONS) {
        @branchHint(.cold);
        return error.MaxIterationsReached;
    }
    if (line_table.lines.len < SORT_THRESHOLD) {
        insertsort(line_table, s);
        return;
    }
    const pivot = median_of_3(line_table, s);
    var i: isize = -1;
    var j = line_table.lines.len;

    while (true) {
        i += 1;
        while (Line.cmp(
            s,
            line_table.lines[@intCast(i)],
            line_table.contents,
            pivot,
            line_table.contents,
        ) == -1) : (i += 1) {}
        j -= 1;
        while (Line.cmp(
            s,
            line_table.lines[j],
            line_table.contents,
            pivot,
            line_table.contents,
        ) == 1) : (j -= 1) {}
        if (@as(usize, @intCast(i)) > j) break;
        std.mem.swap(Line, &line_table.lines[@intCast(i)], &line_table.lines[j]);
    }
    try quicksort(
        .{ .lines = line_table.lines[0..@intCast(i)], .contents = line_table.contents },
        s,
        iteration + 1,
    );
    try quicksort(
        .{
            .lines = line_table.lines[@intCast(i)..line_table.lines.len],
            .contents = line_table.contents,
        },
        s,
        iteration + 1,
    );
}

test "insertsort" {
    const test_gpa = std.testing.allocator;
    const contents =
        \\zebra
        \\apple
        \\banana
        \\
    ;
    var lines: [3]Line = .{
        Line.init(contents[0..5], 0, null, ' '),
        Line.init(contents[6..11], 6, null, ' '),
        Line.init(contents[12..18], 12, null, ' '),
    };
    var s = Settings{};
    defer s.deinit(test_gpa);
    insertsort(.{ .lines = &lines, .contents = contents }, &s);
    try std.testing.expectEqualStrings("apple", lines[0].string(contents));
    try std.testing.expectEqualStrings("banana", lines[1].string(contents));
    try std.testing.expectEqualStrings("zebra", lines[2].string(contents));
}

test "mergesort" {
    const test_gpa = std.testing.allocator;
    const contents = "qazwsxedcrfvtgbyhnujmikolp";
    var lines: [26]Line = undefined;
    for (0..26) |i| {
        lines[i] = Line.init(contents[i .. i + 1], i, null, ' ');
    }
    var s = Settings{};
    defer s.deinit(test_gpa);
    try mergesort(test_gpa, .{ .lines = &lines, .contents = contents }, &s);
    for (0..26) |k| {
        try std.testing.expectEqual(@as(u8, @intCast('a' + k)), lines[k].string(contents)[0]);
    }
}

test "quicksort" {
    const test_gpa = std.testing.allocator;
    const contents = "qazwsxedcrfvtgbyhnujmikolp";
    var lines: [26]Line = undefined;
    for (0..26) |i| {
        lines[i] = Line.init(contents[i .. i + 1], i, null, ' ');
    }
    var s = Settings{};
    defer s.deinit(test_gpa);
    try quicksort(.{ .lines = &lines, .contents = contents }, &s, 0);
    for (0..26) |k| {
        try std.testing.expectEqual(@as(u8, @intCast('a' + k)), lines[k].string(contents)[0]);
    }
}
