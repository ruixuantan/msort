const std = @import("std");
const msort = @import("msort");

pub fn main() !void {
    defer std.process.exit(0);
    errdefer std.process.exit(1);

    var allocator: std.heap.DebugAllocator(.{}) = .init;
    defer {
        const check = allocator.deinit();
        if (check == .leak) {
            std.log.err("memory leak detected", .{});
            std.process.exit(1);
        }
    }
    const gpa = allocator.allocator();

    const raw_args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, raw_args);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout();
    defer stdout.close();
    var stdout_writer = stdout.writer(&stdout_buffer);

    const parsed_args = try msort.Args.parse(gpa, raw_args, &stdout_writer);
    if (parsed_args == null) return;
    const args = parsed_args.?;
    defer args.deinit(gpa);
    try args.validate(&stdout_writer);

    const input_buffer = try gpa.alignedAlloc(u8, null, args.input_buffer_size());
    defer gpa.free(input_buffer);

    var input = try msort.Input.init(gpa, &args, input_buffer, args.line_table_size());
    defer input.deinit();

    const output_buffer = try gpa.alloc(u8, args.output_buffer_size());
    defer gpa.free(output_buffer);
    var output = try msort.Output.init(gpa, &args, output_buffer);
    defer output.cleanup();

    var run: usize = 0;
    while (input.has_next()) : (run += 1) {
        const line_table = try input.next();
        switch (args.sort_algorithm) {
            .quicksort => try msort.sort.quicksort(line_table, &args, 0),
            else => try msort.sort.mergesort(gpa, line_table, &args),
        }

        if (run == 0 and !input.has_next()) {
            @branchHint(.cold);
            try output.write_to_file(line_table);
            return;
        } else if (run == 0) {
            try output.create_tmp_dir();
        }
        try output.write_to_tmp(line_table, run);
    }
    if (run == 0) return;

    var writer = try output.get_writer();
    var merge = try msort.Merge.init(gpa, &args, input_buffer, run, &writer);
    defer merge.deinit();
    try merge.kway();
}
