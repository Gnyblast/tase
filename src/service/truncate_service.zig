const std = @import("std");
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
            std.log.info("truncating file {s}", .{file_name});
            var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
            switch (std.meta.stringToEnum(enums.TruncateFrom, pruner.log_action.truncate_settings.?.from.?) orelse return TaseNativeErrors.InvalidTruncateFromFieldValue) {
                .bottom => {
                    try processForBottom(pruner, &file);
                },
                .top => {
                    try processForTop(pruner, &file);
                },
            }
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
    const keep = @as(u64, @intCast(pruner.log_action.truncate_settings.?.size.?));
    switch (std.meta.stringToEnum(enums.TruncateBy, pruner.log_action.truncate_settings.?.by.?) orelse return TaseNativeErrors.InvalidTruncateByFieldValue) {
        .size => try keepBottomBySize(file, keep),
        .line => try keepBottomByLine(file, keep),
    }
}

fn processDeleteBottom(pruner: Pruner, file: *File) !void {
    const del = @as(u64, @intCast(pruner.log_action.truncate_settings.?.size.?));
    switch (std.meta.stringToEnum(enums.TruncateBy, pruner.log_action.truncate_settings.?.by.?) orelse return TaseNativeErrors.InvalidTruncateByFieldValue) {
        .size => try deleteBottomBySize(file, del),
        .line => try deleteBottomByLine(file, del),
    }
}

fn keepBottomBySize(file: *File, keep: u64) !void {
    const size = try file.getEndPos();

    if (keep >= size) return;

    const from = size - @as(u64, @intCast(keep));
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
                lines += 1;
                if (lines == keep) {
                    const from = @as(u64, @intCast(pos)) + i + 1;
                    try shiftForward(file, from);
                    return;
                }
            }
        }
    }
}

fn deleteBottomBySize(file: *File, del: u64) !void {
    const size = try file.getEndPos();
    if (del >= size) {
        try file.setEndPos(0);
        return;
    }

    try keepTopBySize(file, size - del);
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
    const keep = @as(u64, @intCast(pruner.log_action.truncate_settings.?.size.?));
    switch (std.meta.stringToEnum(enums.TruncateBy, pruner.log_action.truncate_settings.?.by.?) orelse return TaseNativeErrors.InvalidTruncateByFieldValue) {
        .size => try keepTopBySize(file, keep),
        .line => try keepTopByLine(file, keep),
    }
}

fn processDeleteTop(pruner: Pruner, file: *File) !void {
    const del = @as(u64, @intCast(pruner.log_action.truncate_settings.?.size.?));
    switch (std.meta.stringToEnum(enums.TruncateBy, pruner.log_action.truncate_settings.?.by.?) orelse return TaseNativeErrors.InvalidTruncateByFieldValue) {
        .size => try deleteTopBySize(file, del),
        .line => try deleteTopByLine(file, del),
    }
}

fn keepTopBySize(file: *File, keep: u64) !void {
    try file.setEndPos(keep);
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

fn deleteTopBySize(file: *File, del: u64) !void {
    const size = try file.getEndPos();

    if (del >= size) {
        try file.setEndPos(0);
        return;
    }

    const from = size - @as(u64, @intCast(del));
    try keepBottomBySize(file, from);
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
