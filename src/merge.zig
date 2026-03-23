const std = @import("std");
const Args = @import("argparse.zig").Args;

pub const Merge = struct {
    gpa: std.mem.Allocator,
    args: *const Args,
    buffer: []u8,
    files: std.ArrayList(std.fs.File),
    readers: std.ArrayList(*std.fs.File.Reader),
    num_runs: usize,
    writer: *std.fs.File.Writer,

    const HeapNode = struct { run_idx: usize, string: []const u8 };

    fn compare(_: void, a: HeapNode, b: HeapNode) std.math.Order {
        const key_order = std.mem.order(u8, a.string, b.string);
        if (key_order != .eq) {
            return key_order;
        }
        return std.math.order(a.run_idx, b.run_idx);
    }

    const Heap = std.PriorityQueue(HeapNode, void, compare);

    pub fn init(
        gpa: std.mem.Allocator,
        args: *const Args,
        buffer: []u8,
        num_runs: usize,
        writer: *std.fs.File.Writer,
    ) !Merge {
        var files = try std.ArrayList(std.fs.File).initCapacity(gpa, num_runs);
        var readers = try std.ArrayList(*std.fs.File.Reader).initCapacity(gpa, num_runs);
        const run_buffer_size = @divFloor(buffer.len, num_runs);
        for (0..num_runs) |i| {
            const filename = try std.fmt.allocPrint(gpa, "{s}/{d}.tmp", .{ args.tmp_dir, i });
            defer gpa.free(filename);
            const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
            files.appendAssumeCapacity(file);
            const r = try gpa.create(std.fs.File.Reader);
            r.* = file.reader(buffer[i * run_buffer_size .. (i + 1) * run_buffer_size]);
            readers.appendAssumeCapacity(r);
        }

        return .{
            .gpa = gpa,
            .buffer = buffer,
            .args = args,
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
            file.close();
        }
        self.files.deinit(self.gpa);
    }

    fn next_heap_node(self: *Merge, run_no: usize) !?HeapNode {
        std.debug.assert(run_no < self.num_runs);
        const string = self.readers.items[run_no].interface.takeDelimiterInclusive(
            self.args.delimiter,
        ) catch |err| {
            switch (err) {
                error.EndOfStream => return null,
                else => return err,
            }
        };
        return .{ .run_idx = run_no, .string = string };
    }

    pub fn kway(self: *Merge) !void {
        var heap = Heap.init(self.gpa, undefined);
        defer heap.deinit();
        for (0..self.num_runs) |run_no| {
            if (try self.next_heap_node(run_no)) |node| {
                try heap.add(node);
            }
        }

        var writer_buffer_size: usize = 0;
        while (heap.items.len > 0) {
            std.debug.assert(heap.items.len <= self.num_runs);
            const node = heap.remove();
            if (writer_buffer_size + node.string.len > self.writer.interface.buffer.len) {
                try self.writer.interface.flush();
                writer_buffer_size = 0;
            }

            try self.writer.interface.writeAll(node.string);
            if (try self.next_heap_node(node.run_idx)) |next_node| {
                try heap.add(next_node);
            }
        }
        try self.writer.interface.flush();
    }
};

test "Merge: kway" {
    const test_gpa = std.testing.allocator;
    const args = Args{ .tmp_dir = "test_data/tmp" };
    const buffer = try test_gpa.alloc(u8, 50);
    defer test_gpa.free(buffer);

    var tmp_file = try std.fs.cwd().createFile("test_data/tmp/stdout", .{});
    defer std.fs.cwd().deleteFile("test_data/tmp/stdout") catch {};
    var output_buffer: [1024]u8 = undefined;
    var writer = tmp_file.writer(&output_buffer);

    var merge = try Merge.init(test_gpa, &args, buffer, 2, &writer);
    defer merge.deinit();
    try merge.kway();

    var reader_buffer: [1024]u8 = undefined;
    tmp_file.close();
    tmp_file = try std.fs.cwd().openFile("test_data/tmp/stdout", .{ .mode = .read_only });
    defer tmp_file.close();
    var reader = tmp_file.reader(&reader_buffer);
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
