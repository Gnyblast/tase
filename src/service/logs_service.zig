const std = @import("std");
const datetime = @import("datetime").datetime;
const Regex = @import("libregex").Regex;

const configs = @import("../app/config.zig");
const enums = @import("../enum/config_enum.zig");
const compressionFactory = @import("../factory/compression_factory.zig");

const Allocator = std.mem.Allocator;

pub const LogService = struct {
    timezone: datetime.Timezone,
    directory: []const u8,
    matcher: []const u8,
    log_action: configs.LogAction,

    pub fn init(timezone: datetime.Timezone, directory: []const u8, matcher: []const u8, log_action: configs.LogAction) LogService {
        return LogService{
            .timezone = timezone,
            .directory = directory,
            .matcher = matcher,
            .log_action = log_action,
        };
    }

    pub fn run(self: LogService) !void {
        try self.log_action.checkActionValidity();
        var da: std.heap.DebugAllocator(.{}) = .init;
        defer {
            const leaks = da.deinit();
            std.debug.assert(leaks == .ok);
        }

        const allocator = da.allocator();

        std.log.scoped(.logs).info("Starting clean up for {s}", .{self.directory});
        switch (std.meta.stringToEnum(enums.ActionStrategy, self.log_action.strategy) orelse return error.InvalidStrategy) {
            enums.ActionStrategy.delete => return self.doDelete(allocator),
            enums.ActionStrategy.rotate => return self.doRotate(allocator),
            enums.ActionStrategy.truncate => return self.doTruncate(),
        }
    }

    fn doRotate(self: LogService, allocator: Allocator) !void {
        std.log.info("Processing file rotations for path: {s}", .{self.directory});
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const files = try findRegexMatchesInDir(arena.allocator(), self.directory, self.matcher);
        for (files.items) |file_name| {
            //TODO check rotation conditions, by and size
            if (self.log_action.compress.?) {
                var paths = [_][]const u8{ self.directory, file_name };
                const path = std.fs.path.join(allocator, &paths) catch |err| {
                    std.log.scoped(.logs).err("error joining paths: {s}/{s}, {}", .{ self.directory, file_name, err });
                    continue;
                };
                defer allocator.free(path);

                const compress_type = std.meta.stringToEnum(enums.CompressType, self.log_action.compression_type.?) orelse {
                    std.log.scoped(.logs).err("error getting compression type", .{});
                    continue;
                };

                var writer = std.ArrayList(u8).init(allocator);
                defer writer.deinit();
                var reader = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch |err| {
                    std.log.scoped(.logs).err("error getting file reader for {s}: {}", .{ path, err });
                    continue;
                };
                defer reader.close();

                const compressor = compressionFactory.getCompressor(compress_type);
                compressor.compress(reader.reader(), writer.writer(), .{ .level = @enumFromInt(self.log_action.compression_level.?) }) catch |err| {
                    std.log.scoped(.logs).err("error compressing file {s}: {}", .{ path, err });
                    continue;
                };

                //TODO: Make timestamp
                const compress_path = std.fmt.allocPrint(allocator, "{s}.{s}", .{ path, compress_type.getCompressionExtension() }) catch |err| {
                    std.log.scoped(.logs).err("error generating file name for {s}: {}", .{ path, err });
                    continue;
                };
                defer allocator.free(compress_path);

                const compressed_file = std.fs.createFileAbsolute(compress_path, .{ .mode = 0o666 }) catch |err| {
                    std.log.scoped(.logs).err("unable to create compressed file {s}: {}", .{ compress_path, err });
                    continue;
                };
                defer compressed_file.close();
                _ = compressed_file.write(writer.items) catch |err| {
                    std.log.scoped(.logs).err("unable to write compressed file {s}: {}", .{ path, err });
                    continue;
                };
                // if (write_size < 0) {
                // }
            }
        }
    }

    fn doDelete(self: LogService, allocator: Allocator) !void {
        std.log.info("Processing file deletions for path: {s}", .{self.directory});
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const files = try findRegexMatchesInDir(arena.allocator(), self.directory, self.matcher);

        for (files.items) |file_name| {
            var paths = [_][]const u8{ self.directory, file_name };
            const path = std.fs.path.join(allocator, &paths) catch |err| {
                std.log.scoped(.logs).err("error joining paths: {s}/{s}, {}", .{ self.directory, file_name, err });
                continue;
            };
            defer allocator.free(path);

            if (shouldDelete(self.log_action.@"if", path, self.timezone)) {
                std.log.scoped(.logs).info("deleting file: {s}", .{file_name});
                try std.fs.deleteFileAbsolute(path);
            }
        }
    }

    fn doTruncate(_: LogService) !void {}
};

fn shouldDelete(ifOpr: configs.IfOperation, path: []u8, timezone: datetime.Timezone) bool {
    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_write }) catch |err| {
        std.log.scoped(.logs).err("error opening file: {s} {}", .{ path, err });
        return false;
    };
    defer file.close();

    const file_stats = file.metadata() catch |err| {
        std.log.scoped(.logs).err("error retrieving file metadata: {s} {}", .{ path, err });
        return false;
    };

    switch (std.meta.stringToEnum(enums.ActionBy, ifOpr.condition) orelse return false) {
        .days => {
            return shouldDeleteByDays(ifOpr, file_stats, timezone);
        },
        .size => {
            return shouldDeleteBySize(ifOpr, file_stats);
        },
        else => {
            return false;
        },
    }
}

fn shouldDeleteByDays(ifOpr: configs.IfOperation, file_stats: std.fs.File.Metadata, timezone: datetime.Timezone) bool {
    const mtime_ns = file_stats.modified();

    const mtime_ms: i64 = @as(i64, @intCast(@divFloor(mtime_ns, std.time.ns_per_ms)));

    const modification = datetime.Datetime.fromTimestamp(mtime_ms).shiftTimezone(timezone);
    const now = datetime.Datetime.now().shiftTimezone(timezone).shiftDays(-ifOpr.operand);
    switch (std.meta.stringToEnum(enums.Operators, ifOpr.operator) orelse return false) {
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

fn shouldDeleteBySize(ifOpr: configs.IfOperation, file_stats: std.fs.File.Metadata) bool {
    switch (std.meta.stringToEnum(enums.Operators, ifOpr.operator) orelse return false) {
        .@">" => {
            return file_stats.size() > ifOpr.operand;
        },
        .@"<" => {
            return file_stats.size() < ifOpr.operand;
        },
        .@"=" => {
            return file_stats.size() == ifOpr.operand;
        },
    }
}

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
