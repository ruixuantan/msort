const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const line = @import("line.zig");
const Line = line.Line;
const Settings = @import("settings.zig").Settings;

pub const Merge = struct {
    gpa: Allocator,
    io: Io,
    s: *const Settings,
    buffer: []u8,
    files: std.ArrayList(File),
    readers: std.ArrayList(*File.Reader),
    num_runs: usize,
    writer: *File.Writer,

    const HeapNode = struct { run_idx: usize, string: []const u8 };

    const HeapContext = struct { s: *const Settings };

    inline fn compare_strings(ctx: HeapContext, a: []const u8, b: []const u8) i8 {
        const a_line = Line.init(a, 0, ctx.s.first_key, ctx.s.separator);
        const b_line = Line.init(b, 0, ctx.s.first_key, ctx.s.separator);
        return Line.cmp(ctx.s, a_line, a, b_line, b);
    }

    fn compare(ctx: HeapContext, a: HeapNode, b: HeapNode) std.math.Order {
        const key_order = compare_strings(ctx, a.string, b.string);
        if (key_order < 0) {
            return .lt;
        } else if (key_order > 0) {
            return .gt;
        } else {
            return std.math.order(a.run_idx, b.run_idx);
        }
    }

    const Heap = std.PriorityQueue(HeapNode, HeapContext, compare);

    pub fn init(
        gpa: Allocator,
        io: Io,
        s: *const Settings,
        buffer: []u8,
        num_runs: usize,
        writer: *File.Writer,
    ) !Merge {
        std.debug.assert(num_runs > 0);
        var files = try std.ArrayList(File).initCapacity(gpa, num_runs);
        var readers = try std.ArrayList(*File.Reader).initCapacity(gpa, num_runs);
        const run_buffer_size = @divFloor(buffer.len, num_runs);
        for (0..num_runs) |i| {
            const filename = try std.fmt.allocPrint(gpa, "{s}/{d}.tmp", .{ s.tmp_dir, i });
            defer gpa.free(filename);
            const file = try Dir.cwd().openFile(io, filename, .{ .mode = .read_only });
            files.appendAssumeCapacity(file);
            const r = try gpa.create(File.Reader);
            r.* = file.reader(io, buffer[i * run_buffer_size .. (i + 1) * run_buffer_size]);
            readers.appendAssumeCapacity(r);
        }

        return .{
            .gpa = gpa,
            .io = io,
            .buffer = buffer,
            .s = s,
            .files = files,
            .readers = readers,
            .num_runs = num_runs,
            .writer = writer,
        };
    }

    pub fn deinit(self: *Merge) void {
        for (self.readers.items) |reader| {
            self.gpa.destroy(reader);
        }
        self.readers.deinit(self.gpa);
        for (self.files.items) |file| {
            file.close(self.io);
        }
        self.files.deinit(self.gpa);
    }

    fn next_heap_node(self: *Merge, run_no: usize) !?HeapNode {
        std.debug.assert(run_no < self.num_runs);
        const string = self.readers.items[run_no].interface.takeDelimiterInclusive(
            self.s.delimiter,
        ) catch |err| {
            switch (err) {
                error.EndOfStream => return null,
                else => return err,
            }
        };
        return .{ .run_idx = run_no, .string = string };
    }

    pub fn kway(self: *Merge) !void {
        const heap_context = HeapContext{ .s = self.s };
        var heap = Heap.initContext(heap_context);
        defer heap.deinit(self.gpa);
        for (0..self.num_runs) |run_no| {
            if (try self.next_heap_node(run_no)) |node| {
                try heap.push(self.gpa, node);
            }
        }

        var writer_buffer_size: usize = 0;
        while (heap.items.len > 0) {
            std.debug.assert(heap.items.len <= self.num_runs);
            var node = heap.pop().?;
            if (writer_buffer_size + node.string.len > self.writer.interface.buffer.len) {
                try self.writer.interface.flush();
                writer_buffer_size = 0;
            }
            try self.writer.interface.writeAll(node.string);
            if (try self.next_heap_node(node.run_idx)) |n| try heap.push(self.gpa, n);

            if (self.s.unique) {
                while (heap.peek()) |peek_node| {
                    if (compare_strings(heap_context, node.string, peek_node.string) != 0) break;
                    node = heap.pop().?;
                    if (try self.next_heap_node(node.run_idx)) |n| try heap.push(self.gpa, n);
                }
            }
        }
        try self.writer.interface.flush();
    }
};

test "Merge: kway" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var s = Settings{
        .tmp_dir = "test_data/tmp",
    };
    const buffer = try gpa.alloc(u8, 50);
    defer gpa.free(buffer);

    var tmp_file = try Dir.cwd().createFile(io, "test_data/tmp/stdout", .{});
    defer Dir.cwd().deleteFile(io, "test_data/tmp/stdout") catch {};
    var output_buffer: [1024]u8 = undefined;
    var writer = tmp_file.writer(io, &output_buffer);

    var merge = try Merge.init(gpa, io, &s, buffer, 2, &writer);
    defer merge.deinit();
    try merge.kway();

    var reader_buffer: [1024]u8 = undefined;
    tmp_file.close(io);
    tmp_file = try Dir.cwd().openFile(io, "test_data/tmp/stdout", .{ .mode = .read_only });
    defer tmp_file.close(io);
    var reader = tmp_file.reader(io, &reader_buffer);
    const expected =
        \\alligator
        \\apple
        \\banana
        \\bat
        \\blackberry
        \\blueberry
        \\cat
        \\cherry
        \\donkey
        \\elephant
        \\fox
        \\giraffe
        \\grape
        \\hippothamus
        \\iguana
        \\jaguar
        \\kangaroo
        \\lion
        \\monkey
        \\narwhal
        \\octopus
        \\orange
        \\pear
        \\penguin
        \\pineapple
        \\quail
        \\rabbit
        \\raspberry
        \\salmon
        \\strawberry
        \\tiger
        \\unicorn
        \\watermelon
        \\zebra
        \\
    ;
    const contents = try reader.interface.take(expected.len);
    try std.testing.expectEqualStrings(expected, contents);
    try std.testing.expectEqual(error.EndOfStream, reader.interface.take(1));
}
