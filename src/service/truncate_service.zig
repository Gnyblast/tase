const std = @import("std");
const testing = std.testing;
const datetime = @import("datetime").datetime;
const configs = @import("../app/config.zig");
const helper = @import("prune_helper.zig");
const enums = @import("../enum/config_enum.zig");
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;
const Pruner = @import("./pruner.zig").Pruner;
const File = std.fs.File;

const Allocator = std.mem.Allocator;

pub fn doTruncate(pruner: Pruner, allocator: Allocator) !void {
    std.log.scoped(.logs).info("Processing file truncates for path: {s}", .{pruner.directory});
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    std.log.debug("Matcher is: {s}", .{pruner.matcher});
    const files = try helper.findRegexMatchesInDir(arena.allocator(), pruner.directory, pruner.matcher);
    std.log.debug("Matched files are: {any}", .{files.items});
    for (files.items) |file_name| {
        var paths = [_][]const u8{ pruner.directory, file_name };
        const path = std.fs.path.join(allocator, &paths) catch |err| {
            std.log.scoped(.logs).err("error joining paths: {s}/{s}, {any}", .{ pruner.directory, file_name, err });
            continue;
        };
        defer allocator.free(path);

        if (helper.shouldProcess(pruner.log_action.@"if".?, path, pruner.timezone)) {
            std.log.debug("truncating file {s}", .{path});
            var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
            switch (std.meta.stringToEnum(enums.TruncateFrom, pruner.log_action.truncate_settings.?.from.?) orelse return TaseNativeErrors.InvalidTruncateFromFieldValue) {
                .bottom => {
                    try processForBottom(pruner, &file);
                },
                .top => {
                    try processForTop(pruner, &file);
                },
            }
            std.log.info("truncated file {s}", .{path});
        }
    }
}

fn processForBottom(pruner: Pruner, file: *File) !void {
    switch (std.meta.stringToEnum(enums.TruncateAction, pruner.log_action.truncate_settings.?.action.?) orelse return TaseNativeErrors.InvalidTruncateActionFieldValue) {
        .keep => try processKeepBottom(pruner, file),
        .delete => try processDeleteBottom(pruner, file),
    }
}

fn processKeepBottom(pruner: Pruner, file: *File) !void {
    if (pruner.log_action.truncate_settings.?.size.? > 0) {
        const keep = @as(u64, @intCast(pruner.log_action.truncate_settings.?.size.?));
        return try keepBottomBySize(file, keep);
    }

    if (pruner.log_action.truncate_settings.?.lines.? > 0) {
        const keep = @as(u64, @intCast(pruner.log_action.truncate_settings.?.lines.?));
        return try keepBottomByLine(file, keep);
    }
}

fn processDeleteBottom(pruner: Pruner, file: *File) !void {
    if (pruner.log_action.truncate_settings.?.size.? > 0) {
        const del = @as(u64, @intCast(pruner.log_action.truncate_settings.?.size.?));
        return try deleteBottomBySize(file, del);
    }

    if (pruner.log_action.truncate_settings.?.lines.? > 0) {
        const del = @as(u64, @intCast(pruner.log_action.truncate_settings.?.lines.?));
        return try deleteBottomByLine(file, del);
    }
}

fn keepBottomBySize(file: *File, keep_mb: u64) !void {
    const size = try file.getEndPos();
    const bytes_to_keep = keep_mb * 1024 * 1024;

    if (bytes_to_keep >= size) return;

    const from = size - @as(u64, @intCast(bytes_to_keep));
    try shiftForward(file, from);
}

fn keepBottomByLine(file: *File, keep: usize) !void {
    if (keep == 0) {
        try file.setEndPos(0);
        return;
    }

    const size = try file.getEndPos();
    var pos: i64 = @intCast(size);

    var buf: [64 * 1024]u8 = undefined;
    var lines: usize = 0;

    while (pos > 0) {
        const chunk = @min(buf.len, @as(usize, @intCast(pos)));
        pos -= @intCast(chunk);

        try file.seekTo(@intCast(pos));
        const n = try file.read(buf[0..chunk]);

        var i: usize = n;
        while (i > 0) {
            i -= 1;
            if (buf[i] == '\n') {
                if (lines == keep) {
                    const from = @as(u64, @intCast(pos)) + i + 1;
                    try shiftForward(file, from);
                    return;
                }
                lines += 1;
            }
        }
    }
}

fn deleteBottomBySize(file: *File, del_mb: u64) !void {
    const bytes_to_del = del_mb * 1024 * 1024;
    const size = try file.getEndPos();
    if (bytes_to_del >= size) {
        try file.setEndPos(0);
        return;
    }

    const mb_to_del: usize = (size - bytes_to_del) / 1024 / 1024;
    try keepTopBySize(file, mb_to_del);
}

fn deleteBottomByLine(file: *File, del: usize) !void {
    if (del == 0) return;

    // Count total lines
    var buf: [64 * 1024]u8 = undefined;

    var total: usize = 0;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        for (buf[0..n]) |c| {
            if (c == '\n') total += 1;
        }
    }

    if (del >= total) {
        try file.setEndPos(0);
        return;
    }

    try keepTopByLine(file, total - del);
}

fn processForTop(pruner: Pruner, file: *File) !void {
    switch (std.meta.stringToEnum(enums.TruncateAction, pruner.log_action.truncate_settings.?.action.?) orelse return TaseNativeErrors.InvalidTruncateActionFieldValue) {
        .keep => try processKeepTop(pruner, file),
        .delete => try processDeleteTop(pruner, file),
    }
}

fn processKeepTop(pruner: Pruner, file: *File) !void {
    if (pruner.log_action.truncate_settings.?.size.? > 0) {
        const keep = @as(u64, @intCast(pruner.log_action.truncate_settings.?.size.?));
        return try keepTopBySize(file, keep);
    }

    if (pruner.log_action.truncate_settings.?.lines.? > 0) {
        const keep = @as(u64, @intCast(pruner.log_action.truncate_settings.?.lines.?));
        return try keepTopByLine(file, keep);
    }
}

fn processDeleteTop(pruner: Pruner, file: *File) !void {
    if (pruner.log_action.truncate_settings.?.size.? > 0) {
        const del = @as(u64, @intCast(pruner.log_action.truncate_settings.?.size.?));
        return try deleteTopBySize(file, del);
    }

    if (pruner.log_action.truncate_settings.?.lines.? > 0) {
        const del = @as(u64, @intCast(pruner.log_action.truncate_settings.?.lines.?));
        return try deleteTopByLine(file, del);
    }
}

fn keepTopBySize(file: *File, keep_mb: u64) !void {
    const bytes_to_keep = keep_mb * 1024 * 1024;
    try file.setEndPos(bytes_to_keep);
}

fn keepTopByLine(file: *File, keep: usize) !void {
    if (keep == 0) {
        try file.setEndPos(0);
        return;
    }

    // Always start from beginning
    try file.seekTo(0);

    var buf: [64 * 1024]u8 = undefined;

    var lines: usize = 0;
    var pos: u64 = 0;

    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;

        for (buf[0..n], 0..) |c, i| {
            if (c == '\n') {
                lines += 1;
                if (lines == keep) {
                    pos += i + 1;
                    try file.setEndPos(pos);
                    return;
                }
            }
        }

        pos += n;
    }
}

fn deleteTopBySize(file: *File, del_mb: u64) !void {
    const size = try file.getEndPos();
    const bytes_to_del = del_mb * 1024 * 1024;

    if (bytes_to_del >= size) {
        try file.setEndPos(0);
        return;
    }

    const mb_to_keep = (size - @as(u64, @intCast(bytes_to_del))) / 1024 / 1024;
    try keepBottomBySize(file, mb_to_keep);
}

fn deleteTopByLine(file: *File, del: usize) !void {
    if (del == 0) return;

    var buf: [64 * 1024]u8 = undefined;

    var lines: usize = 0;
    var del_size: usize = 0;
    var pos: usize = 0;

    outer: while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        for (buf[0..n]) |c| {
            if (c == '\n') {
                lines += 1;
                del_size += pos;
                pos = 0;
            }

            if (lines >= del) {
                del_size += 1;
                break :outer;
            }
            pos += 1;
        }
    }

    const from = @as(u64, @intCast(del_size));
    try shiftForward(file, from);
}

fn shiftForward(file: *File, from: u64) !void {
    const end = try file.getEndPos();

    var read_pos = from;
    var write_pos: u64 = 0;

    var buf: []u8 = try std.heap.page_allocator.alloc(u8, 1024 * 64);
    defer std.heap.page_allocator.free(buf);

    while (read_pos < end) {
        try file.seekTo(read_pos);
        const n = try file.read(buf);
        if (n == 0) break;

        try file.pwriteAll(buf[0..n], write_pos);

        read_pos += n;
        write_pos += n;
    }

    try file.setEndPos(write_pos);
}

test "doTruncateTest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tz = datetime.timezones.Asia.Nicosia;
    var delete_from_top_lines = configs.LogAction{
        .strategy = enums.ActionStrategy.truncate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "gt",
            .operand = 5,
        },
        .truncate_settings = .{
            .lines = 1,
            .action = enums.TruncateAction.delete.str(),
            .from = enums.TruncateFrom.top.str(),
        },
    };
    var delete_from_top_size = configs.LogAction{
        .strategy = enums.ActionStrategy.truncate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "gt",
            .operand = 5,
        },
        .truncate_settings = .{
            .size = 1,
            .action = enums.TruncateAction.delete.str(),
            .from = enums.TruncateFrom.top.str(),
        },
    };
    var keep_from_top_lines = configs.LogAction{
        .strategy = enums.ActionStrategy.truncate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "gt",
            .operand = 5,
        },
        .truncate_settings = .{
            .lines = 1,
            .action = enums.TruncateAction.keep.str(),
            .from = enums.TruncateFrom.top.str(),
        },
    };
    var keep_from_top_size = configs.LogAction{
        .strategy = enums.ActionStrategy.truncate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "gt",
            .operand = 5,
        },
        .truncate_settings = .{
            .size = 1,
            .action = enums.TruncateAction.keep.str(),
            .from = enums.TruncateFrom.top.str(),
        },
    };
    var delete_from_bottom_lines = configs.LogAction{
        .strategy = enums.ActionStrategy.truncate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "gt",
            .operand = 5,
        },
        .truncate_settings = .{
            .lines = 1,
            .action = enums.TruncateAction.delete.str(),
            .from = enums.TruncateFrom.bottom.str(),
        },
    };
    var delete_from_bottom_size = configs.LogAction{
        .strategy = enums.ActionStrategy.truncate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "gt",
            .operand = 5,
        },
        .truncate_settings = .{
            .size = 1,
            .action = enums.TruncateAction.delete.str(),
            .from = enums.TruncateFrom.bottom.str(),
        },
    };
    var keep_from_bottom_lines = configs.LogAction{
        .strategy = enums.ActionStrategy.truncate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "gt",
            .operand = 5,
        },
        .truncate_settings = .{
            .lines = 1,
            .action = enums.TruncateAction.keep.str(),
            .from = enums.TruncateFrom.bottom.str(),
        },
    };
    var keep_from_bottom_size = configs.LogAction{
        .strategy = enums.ActionStrategy.truncate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "gt",
            .operand = 5,
        },
        .truncate_settings = .{
            .size = 1,
            .action = enums.TruncateAction.keep.str(),
            .from = enums.TruncateFrom.bottom.str(),
        },
    };

    const TestCase = struct {
        log_action: *configs.LogAction,
        matcher: []const u8,
    };
    var tcs = [_]TestCase{
        .{
            .log_action = &delete_from_top_lines,
            .matcher = "mock-truncate.*",
        },
        .{
            .log_action = &delete_from_top_size,
            .matcher = "mock-truncate.*",
        },
        .{
            .log_action = &keep_from_top_lines,
            .matcher = "mock-truncate.*",
        },
        .{
            .log_action = &keep_from_top_size,
            .matcher = "mock-truncate.*",
        },
        .{
            .log_action = &delete_from_bottom_lines,
            .matcher = "mock-truncate.*",
        },
        .{
            .log_action = &delete_from_bottom_size,
            .matcher = "mock-truncate.*",
        },
        .{
            .log_action = &keep_from_bottom_lines,
            .matcher = "mock-truncate.*",
        },
        .{
            .log_action = &keep_from_bottom_size,
            .matcher = "mock-truncate.*",
        },
    };

    // Multiline pattern
    const pattern =
        \\This is a test line
        \\Another test line
        \\Yet another line with data
        \\--------------------------------
        \\
    ;

    const cwd = try std.fs.realpathAlloc(testing.allocator, "./test/unit-test-dir");
    defer testing.allocator.free(cwd);

    for (&tcs) |tc| {
        var paths = [_][]const u8{ cwd, "mock-truncate.log" };
        const mock_file_path = try std.fs.path.join(testing.allocator, &paths);
        defer testing.allocator.free(mock_file_path);
        var mock_file = try std.fs.createFileAbsolute(mock_file_path, .{});

        const target_size: usize = 10 * 1024 * 1024; // 10 MB
        var written: usize = 0;

        while (written < target_size) {
            _ = try mock_file.write(pattern);
            written += pattern.len;
        }

        defer mock_file.close();
        defer std.fs.deleteFileAbsolute(mock_file_path) catch {};

        const pruner = Pruner.init(
            arena,
            &tz,
            cwd,
            tc.matcher,
            tc.log_action,
        );

        try doTruncate(pruner, testing.allocator);
    }
}
