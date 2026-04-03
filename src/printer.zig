const std = @import("std");
const File = std.fs.File;

pub fn print(comptime message: []const u8) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = File.stderr();
    defer stdout.close();
    var stdout_writer = stdout.writer(&stdout_buffer);
    try stdout_writer.interface.print("{s}\n", .{message});
    try stdout_writer.interface.flush();
}

pub fn print_err(comptime message: []const u8, args: anytype) !void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr = File.stderr();
    defer stderr.close();
    var stderr_writer = stderr.writer(&stderr_buffer);
    try stderr_writer.interface.print(message, args);
    try stderr_writer.interface.flush();
}
