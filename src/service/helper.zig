const std = @import("std");
const datetime = @import("datetime").datetime;
const Regex = @import("libregex").Regex;
const configs = @import("../app/config.zig");
const enums = @import("../enum/config_enum.zig");
const utils = @import("../utils/helper.zig");

const Allocator = std.mem.Allocator;

pub fn findRegexMatchesInDir(arena: Allocator, dir: []const u8, regexp: []const u8) !std.ArrayList([]const u8) {
    var files = try std.fs.openDirAbsolute(dir, .{ .iterate = true, .access_sub_paths = false });
    defer files.close();

    var matchedFiles = std.ArrayList([]const u8).init(arena);

    var f_it = files.iterate();
    while (try f_it.next()) |file| {
        const regex = try Regex.init(arena, regexp, "x");
        defer regex.deinit();

        const matched = regex.matches(file.name) catch |err| {
            std.log.scoped(.cron).err("error matching file {s}: {}", .{ file.name, err });
            continue;
        };

        if (matched) {
            const name_copy = try arena.dupe(u8, file.name);
            try matchedFiles.append(name_copy);
        }
    }

    return matchedFiles;
}

pub fn shouldProcess(ifOpr: configs.IfOperation, path: []u8, timezone: *datetime.Timezone) bool {
    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_write }) catch |err| {
        std.log.scoped(.logs).err("error opening file: {s} {}", .{ path, err });
        return false;
    };
    defer file.close();

    const file_stats = file.metadata() catch |err| {
        std.log.scoped(.logs).err("error retrieving file metadata: {s} {}", .{ path, err });
        return false;
    };

    switch (std.meta.stringToEnum(enums.IfConditions, ifOpr.condition.?) orelse return false) {
        .days => {
            return compareByAge(ifOpr, file_stats, timezone);
        },
        .size => {
            return compareBySize(ifOpr, file_stats);
        },
    }
}

fn compareByAge(ifOpr: configs.IfOperation, file_stats: std.fs.File.Metadata, timezone: *datetime.Timezone) bool {
    const mtime_ns = file_stats.modified();

    const mtime_ms: i64 = @as(i64, @intCast(@divFloor(mtime_ns, std.time.ns_per_ms)));

    const modification = datetime.Datetime.fromTimestamp(mtime_ms).shiftTimezone(timezone.*);
    const now = datetime.Datetime.now().shiftTimezone(timezone.*).shiftDays(-ifOpr.operand.?);
    switch (std.meta.stringToEnum(enums.Operators, ifOpr.operator.?) orelse return false) {
        .@">" => {
            return now.cmp(modification) == .gt;
        },
        .@"<" => {
            return now.cmp(modification) == .lt;
        },
        .@"=" => {
            return now.cmp(modification) == .eq;
        },
    }
}

fn compareBySize(ifOpr: configs.IfOperation, file_stats: std.fs.File.Metadata) bool {
    switch (std.meta.stringToEnum(enums.Operators, ifOpr.operator.?) orelse return false) {
        .@">" => {
            return utils.bytesToMegabytes(file_stats.size()) > @as(f64, @floatFromInt(ifOpr.operand.?));
        },
        .@"<" => {
            return utils.bytesToMegabytes(file_stats.size()) < @as(f64, @floatFromInt(ifOpr.operand.?));
        },
        .@"=" => {
            return utils.bytesToMegabytes(file_stats.size()) == @as(f64, @floatFromInt(ifOpr.operand.?));
        },
    }
}
