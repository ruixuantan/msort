const std = @import("std");
const msort = @import("msort");

pub fn main(init: std.process.Init) !void {
    defer std.process.exit(0);
    errdefer std.process.exit(1);
    const gpa = init.gpa;
    const io = init.io;

    const raw_args = try init.minimal.args.toSlice(gpa);
    defer gpa.free(raw_args);
    const args = try msort.argparse.parse_args(io, raw_args, msort.Args) orelse return;
    const settings = try msort.Settings.from_args(gpa, io, &args);
    defer settings.deinit(gpa);

    const input_buffer = try gpa.alignedAlloc(u8, null, settings.input_buffer_size());
    defer gpa.free(input_buffer);
    var input = try msort.Input.init(gpa, io, &settings, input_buffer, settings.line_table_size());
    defer input.deinit();

    const output_buffer = try gpa.alloc(u8, settings.output_buffer_size());
    defer gpa.free(output_buffer);
    var output = try msort.Output.init(gpa, io, &settings, output_buffer);
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
    var merge = try msort.Merge.init(gpa, io, &settings, input_buffer, run, &writer);
    defer merge.deinit();
    try merge.kway();
}
