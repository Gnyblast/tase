const std = @import("std");
const zig_time = @import("zig-time");
const argsParser = @import("args");
const helpers = @import("../utils/helper.zig");
const configs = @import("../app/config.zig");

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    log_file_dir: []const u8,
    is_agent: bool,
    args: anytype,
) void {
    //? These are to ignore yaml parser logs
    if (scope == .parse or scope == .tokenizer) {
        return;
    }

    const allocator = std.heap.page_allocator;
    createLogDirIfNotExist(log_file_dir) catch |err| {
        std.debug.print("Failed to create logging dir: {}\n", .{err});
        std.process.exit(1);
        return;
    };
    const log_dir = getLogFilePath(log_file_dir);

    const log_file_name = if (is_agent) "tase-agent.log" else "tase-master.log";

    const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ log_dir, log_file_name }) catch |err| {
        std.debug.print("Failed to generate logging path: {}\n", .{err});
        return;
    };
    defer allocator.free(path);

    const file = openOrCreateLogFile(path) catch |err| {
        std.debug.print("Failed to open or create log file, make sure log dir exist with required permissions: {}\n", .{err});
        std.process.exit(1);
        return;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        std.debug.print("Failed to get stat of log file: {}\n", .{err});
        std.process.exit(1);
        return;
    };
    file.seekTo(stat.size) catch |err| {
        std.debug.print("Failed to seek log file: {}\n", .{err});
        std.process.exit(1);
        return;
    };

    const time = std.time.timestamp();
    const time_fmt: []const u8 = "YYYY-MM-DD HH:mm:ss:ms z";
    const time_stamp = getTimeStamp(allocator, time, time_fmt) catch |err| {
        std.debug.print("Failed to get a timestamp: {}\n", .{err});
        return;
    };

    defer allocator.free(time_stamp);
    const prefix = "[{s}] " ++ comptime helpers.toUpperCase(level.asText()) ++ " " ++ "(" ++ @tagName(scope) ++ ") ";

    const message = std.fmt.allocPrint(allocator, prefix ++ format ++ "\n", .{time_stamp} ++ args) catch |err| {
        std.debug.print("Failed to format log message with args: {}\n", .{err});
        return;
    };
    defer allocator.free(message);

    file.writeAll(message) catch |err| {
        std.debug.print("Failed to write to log file: {}\n", .{err});
    };
}

fn createLogDirIfNotExist(log_dir: []const u8) !void {
    _ = std.fs.openDirAbsolute(log_dir, .{}) catch |err| {
        if (err == std.fs.Dir.OpenError.FileNotFound) {
            try std.fs.makeDirAbsolute(log_dir);
            return;
        }

        return err;
    };
}

fn getLogFilePath(lod_dir: []const u8) []const u8 {
    if (lod_dir.len < 1)
        return "/var/log/tase";

    const last_char = lod_dir[lod_dir.len - 1 .. lod_dir.len];
    if (std.mem.eql(u8, last_char, "/")) {
        return lod_dir[0 .. lod_dir.len - 1];
    }

    return lod_dir;
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
    const instant = zig_time.Time.fromTimestamp(timestamp);
    return try instant.formatAlloc(alloc, fmt);
}
