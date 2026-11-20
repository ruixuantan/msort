const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const Settings = @import("settings.zig").Settings;
const Losertree = @import("losertree.zig").Losertree;

pub const Merge = struct {
    gpa: Allocator,
    io: Io,
    s: *const Settings,
    files: std.ArrayList(File),
    readers: std.ArrayList(*File.Reader),
    writer: *File.Writer,

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
        errdefer {
            for (files.items) |file| file.close(io);
            files.deinit(gpa);
        }
        var readers = try std.ArrayList(*File.Reader).initCapacity(gpa, num_runs);
        errdefer {
            for (readers.items) |reader| gpa.destroy(reader);
            readers.deinit(gpa);
        }
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
            .s = s,
            .files = files,
            .readers = readers,
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

    pub fn kway(self: *Merge) !void {
        var tree = try Losertree.init(self.gpa, self.readers.items, self.s);
        defer tree.deinit(self.gpa);

        while (tree.peek()) |record| {
            try self.writer.interface.writeAll(record);
            if (self.s.unique) {
                try tree.advance_unique(self.gpa);
            } else {
                try tree.advance();
            }
        }
        try self.writer.interface.flush();
    }
};

test "Merge: kway" {
    const test_gpa = std.testing.allocator;
    const io = std.testing.io;
    const s = Settings{ .tmp_dir = "test_data/tmp" };
    var buffer: [50]u8 = undefined;

    var tmp_file = try Dir.cwd().createFile(io, "test_data/tmp/stdout", .{});
    defer Dir.cwd().deleteFile(io, "test_data/tmp/stdout") catch {};
    var output_buffer: [1024]u8 = undefined;
    var writer = tmp_file.writer(io, &output_buffer);

    var merge = try Merge.init(test_gpa, io, &s, &buffer, 2, &writer);
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
    try std.testing.expectError(error.EndOfStream, reader.interface.take(1));
}

test "Merge: kway keeps first record for each unique key" {
    const test_gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realPathFileAlloc(io, ".", test_gpa);
    defer test_gpa.free(path);
    try tmp.dir.writeFile(io, .{ .sub_path = "0.tmp", .data = "1 first\n3 third\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "1.tmp", .data = "1 other\n1 again\n2 second\n" });

    const s = Settings{
        .tmp_dir = path,
        .unique = true,
        .first_key = .{ .pos = 0 },
        .keys = &.{.{ .pos = 0 }},
    };
    var input_buffer: [24]u8 = undefined;
    var output_buffer: [12]u8 = undefined;
    {
        const file = try tmp.dir.createFile(io, "output", .{});
        defer file.close(io);
        var writer = file.writer(io, &output_buffer);
        var merge = try Merge.init(test_gpa, io, &s, &input_buffer, 2, &writer);
        defer merge.deinit();
        try merge.kway();
    }

    const file = try tmp.dir.openFile(io, "output", .{ .mode = .read_only });
    defer file.close(io);
    const expected = "1 first\n2 second\n3 third\n";
    var read_buffer: [expected.len]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    try std.testing.expectEqualStrings(expected, try reader.interface.take(expected.len));
    try std.testing.expectError(error.EndOfStream, reader.interface.take(1));
}
