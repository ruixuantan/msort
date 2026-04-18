const std = @import("std");
const Io = std.Io;
const File = std.Io.File;

pub fn print(io: Io, comptime message: []const u8) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = File.stdout();
    defer stdout.close(io);
    var stdout_writer = stdout.writer(io, &stdout_buffer);
    try stdout_writer.interface.print("{s}\n", .{message});
    try stdout_writer.interface.flush();
}

pub fn print_err(io: Io, comptime message: []const u8, args: anytype) !void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr = File.stderr();
    defer stderr.close(io);
    var stderr_writer = stderr.writer(io, &stderr_buffer);
    try stderr_writer.interface.print(message, args);
    try stderr_writer.interface.flush();
}
