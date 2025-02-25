const std = @import("std");
const zig_time = @import("zig-time");
const utils = @import("./app/utils.zig");

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const allocator = std.heap.page_allocator;
    const path = std.fmt.allocPrint(allocator, "{s}", .{"/home/guney/.local/share/tase.log"}) catch |err| {
        std.debug.print("Failed to create log file path: {}\n", .{err});
        return;
    };
    defer allocator.free(path);

    const file = openOrCreateLogFile(path) catch |err| {
        std.debug.print("Failed to open or create log file: {}\n", .{err});
        return;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        std.debug.print("Failed to get stat of log file: {}\n", .{err});
        return;
    };
    file.seekTo(stat.size) catch |err| {
        std.debug.print("Failed to seek log file: {}\n", .{err});
        return;
    };

    const time = std.time.timestamp();
    const time_fmt: []const u8 = "YYYY-MM-DD HH:mm:ss z";
    const time_stamp = getTimeStamp(allocator, time, time_fmt) catch |err| {
        std.debug.print("Failed to get a timestamp: {}\n", .{err});
        return;
    };

    defer allocator.free(time_stamp);
    const prefix = "{s} [" ++ comptime utils.toUpperCase(level.asText()) ++ "] " ++ "(" ++ @tagName(scope) ++ ") ";

    var message_buffer: [4096]u8 = undefined;
    const message = std.fmt.bufPrint(message_buffer[0..], prefix ++ format ++ "\n", .{time_stamp} ++ args) catch |err| {
        std.debug.print("Failed to format log message with args: {}\n", .{err});
        return;
    };
    file.writeAll(message) catch |err| {
        std.debug.print("Failed to write to log file: {}\n", .{err});
    };
}

fn openOrCreateLogFile(path: []const u8) !std.fs.File {
    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_write }) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => return try std.fs.createFileAbsolute(path, .{ .mode = 0o666 }),
        else => {
            return err;
        },
    };

    return file;
}

fn getTimeStamp(alloc: std.mem.Allocator, timestamp: i64, comptime fmt: []const u8) ![]const u8 {
    const instant = zig_time.Time.fromTimestamp(timestamp).setLoc(zig_time.UTC);
    return try instant.formatAlloc(alloc, fmt);
}
