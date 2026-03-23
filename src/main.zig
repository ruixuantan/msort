const std = @import("std");
const msort = @import("msort");

const INPUT_BUFFER_SIZE = 4 * 1024 * 1024;
const LINE_TABLE_SIZE = 2 * 1024 * 1024;
const OUTPUT_BUFFER_SIZE = 1 * 1024 * 1024;

pub fn main() !void {
    defer std.process.exit(0);
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = allocator.deinit();
    const gpa = allocator.allocator();

    const raw_args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, raw_args);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout();
    defer stdout.close();
    var stdout_writer = stdout.writer(&stdout_buffer);

    const parsed_args = try msort.Args.parse(gpa, raw_args, &stdout_writer);
    if (parsed_args == null) std.process.exit(1);
    const args = parsed_args.?;
    defer args.deinit(gpa);
    if (!try args.validate(&stdout_writer)) std.process.exit(1);

    const input_buffer = try gpa.alignedAlloc(u8, null, INPUT_BUFFER_SIZE);
    defer gpa.free(input_buffer);

    var input = try msort.Input.init(gpa, &args, input_buffer, LINE_TABLE_SIZE);
    defer input.deinit();

    const output_buffer = try gpa.alloc(u8, OUTPUT_BUFFER_SIZE);
    defer gpa.free(output_buffer);
    var output = try msort.Output.init(gpa, &args, output_buffer);
    defer output.cleanup();

    var run: usize = 0;
    while (input.has_next()) : (run += 1) {
        const line_table = try input.next();
        switch (args.sort_algorithm) {
            .quicksort => try msort.sort.quicksort(line_table, 0),
            else => try msort.sort.mergesort(gpa, line_table),
        }

        if (run == 0 and !input.has_next()) {
            @branchHint(.cold);
            try output.write_to_file(line_table);
            std.process.exit(0);
        } else if (run == 0) {
            try output.create_tmp_dir();
        }
        try output.write_to_tmp(line_table, run);
    }

    var writer = try output.get_writer();
    var merge = try msort.Merge.init(gpa, &args, input_buffer, run, &writer);
    defer merge.deinit();
    try merge.kway();
}
