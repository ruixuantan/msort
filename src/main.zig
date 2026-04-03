const std = @import("std");
const msort = @import("msort");

pub fn main() !void {
    defer std.process.exit(0);
    errdefer std.process.exit(1);

    var allocator: std.heap.DebugAllocator(.{}) = .init;
    defer {
        const check = allocator.deinit();
        if (check == .leak) {
            msort.printer.print_err("memory leak detected", .{}) catch {};
            std.process.exit(1);
        }
    }
    const gpa = allocator.allocator();

    const raw_args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, raw_args);
    const args = try msort.argparse.parse_args(raw_args, msort.Args) orelse return;
    const settings = try msort.Settings.from_args(gpa, &args);
    defer settings.deinit(gpa);

    const input_buffer = try gpa.alignedAlloc(u8, null, settings.input_buffer_size());
    defer gpa.free(input_buffer);
    var input = try msort.Input.init(gpa, &settings, input_buffer, settings.line_table_size());
    defer input.deinit();

    // const parsed_args = try msort.Args.parse(gpa, raw_args, &stdout_writer);
    // if (parsed_args == null) return;
    // var args = parsed_args.?;
    // defer args.deinit(gpa);
    // try args.validate(&stdout_writer);
    // try args.build_cmp_functions(gpa);

    const output_buffer = try gpa.alloc(u8, settings.output_buffer_size());
    defer gpa.free(output_buffer);
    var output = try msort.Output.init(gpa, &settings, output_buffer);
    defer output.cleanup();

    var run: usize = 0;
    while (input.has_next()) : (run += 1) {
        const line_table = try input.next();
        switch (settings.algo) {
            .quicksort => try msort.sort.quicksort(line_table, &settings, 0),
            else => try msort.sort.mergesort(gpa, line_table, &settings),
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
    var merge = try msort.Merge.init(gpa, &settings, input_buffer, run, &writer);
    defer merge.deinit();
    try merge.kway();
}
