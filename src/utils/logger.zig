const std = @import("std");
const datetime = @import("datetime");
const argsParser = @import("args");
const helpers = @import("../utils/helper.zig");
const configs = @import("../app/config.zig");

pub fn log(
    comptime message_log_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    log_file_dir: []const u8,
    is_agent: bool,
    args: anytype,
    tz: datetime.datetime.Timezone,
    log_level: std.log.Level,
) void {
    //? These are to ignore yaml parser logs
    if (scope == .parse or scope == .tokenizer) {
        return;
    }

    const allocator = std.heap.page_allocator;
    createLogDirIfNotExist(log_file_dir) catch |err| {
        std.debug.print("Failed to create logging dir: {any}\n", .{err});
        std.process.exit(1);
        return;
    };
    const log_dir = getLogFilePath(log_file_dir);

    const log_file_name = if (is_agent) "tase-agent.log" else "tase-master.log";

    const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ log_dir, log_file_name }) catch |err| {
        std.debug.print("Failed to generate logging path: {any}\n", .{err});
        return;
    };
    defer allocator.free(path);

    const file = openOrCreateLogFile(path) catch |err| {
        std.debug.print("Failed to open or create log file, make sure log dir exist with required permissions: {any}\n", .{err});
        std.process.exit(1);
        return;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        std.debug.print("Failed to get stat of log file: {any}\n", .{err});
        std.process.exit(1);
        return;
    };
    file.seekTo(stat.size) catch |err| {
        std.debug.print("Failed to seek log file: {any}\n", .{err});
        std.process.exit(1);
        return;
    };

    const time = std.time.timestamp();
    const time_stamp = getTimeStamp(allocator, time, tz, log_level) catch |err| {
        std.debug.print("Failed to get a timestamp: {any}\n", .{err});
        return;
    };
    defer allocator.free(time_stamp);
    const levelToUpper = helpers.toUpperCase(allocator, message_log_level.asText()) catch |err| {
        std.debug.print("Failed to make log level uppercase: {any}\n", .{err});
        return;
    };
    defer allocator.free(levelToUpper);

    const message = std.fmt.allocPrint(allocator, "[{s}] {s}" ++ " " ++ "(" ++ @tagName(scope) ++ ") " ++ format ++ "\n", .{ time_stamp, levelToUpper } ++ args) catch |err| {
        std.debug.print("Failed to format log message with args: {any}\n", .{err});
        return;
    };
    defer allocator.free(message);

    file.writeAll(message) catch |err| {
        std.debug.print("Failed to write to log file: {any}\n", .{err});
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

fn getTimeStamp(alloc: std.mem.Allocator, timestamp: i64, timezone: datetime.datetime.Timezone, log_level: std.log.Level) ![]const u8 {
    const instant = datetime.datetime.Datetime.fromSeconds(@as(f64, @floatFromInt(timestamp)));
    const now_here = instant.shiftTimezone(timezone);
    if (log_level == .debug)
        return try now_here.formatISO8601(alloc, true);

    return try now_here.formatISO8601(alloc, false);
}
