const std = @import("std");
const datetime = @import("datetime").datetime;
const Regex = @import("libregex").Regex;

const configs = @import("../app/config.zig");
const utils = @import("../utils/helper.zig");
const enums = @import("../enum/config_enum.zig");
const compressionFactory = @import("../factory/compression_factory.zig");
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;

pub const LogService = struct {
    arena: ?Arena,
    timezone: *datetime.Timezone,
    directory: []const u8,
    matcher: []const u8,
    log_action: *configs.LogAction,

    pub fn init(arena: ?Arena, timezone: *datetime.Timezone, directory: []const u8, matcher: []const u8, log_action: *configs.LogAction) LogService {
        return LogService{
            .arena = arena,
            .timezone = timezone,
            .directory = directory,
            .matcher = matcher,
            .log_action = log_action,
        };
    }

    /// Using this method means you need to use runAndDestroy afterwards. Creates arena from the allocator and
    /// free everything at the end of runAndDestroy
    pub fn create(allocator: Allocator, timezone: datetime.Timezone, directory: []const u8, matcher: []const u8, log_action: configs.LogAction) !*LogService {
        var arena = Arena.init(allocator);
        var aa = arena.allocator();

        const log_service = try aa.create(LogService);
        const tz: *datetime.Timezone = try aa.create(datetime.Timezone);
        tz.* = timezone;

        const action = try log_action.dupe(aa);

        const dir = try aa.dupe(u8, directory);
        const regexp = try aa.dupe(u8, matcher);
        log_service.*.arena = arena;
        log_service.*.directory = dir;
        log_service.*.log_action = action;
        log_service.*.matcher = regexp;
        log_service.*.timezone = tz;
        return log_service;
    }

    /// Runs the task and free the memory at the end
    pub fn runAndDestroy(self: *LogService) void {
        defer {
            if (self.arena != null)
                self.arena.?.deinit();
        }
        self.run();
    }

    pub fn run(self: LogService) void {
        var da: std.heap.DebugAllocator(.{}) = .init;
        defer {
            const leaks = da.deinit();
            std.debug.assert(leaks == .ok);
        }

        const allocator = da.allocator();

        self.log_action.checkActionValidity() catch |err| {
            return utils.printError(allocator, err, .logs, "Error running logs service: {s}");
        };

        switch (std.meta.stringToEnum(enums.ActionStrategy, self.log_action.strategy) orelse {
            std.log.scoped(.logs).err("Invalid Strategy {s}", .{self.log_action.strategy});
            return;
        }) {
            enums.ActionStrategy.delete => {
                return self.doDelete(allocator) catch |err| {
                    return utils.printError(allocator, err, .logs, "Error running logs service: {s}");
                };
            },
            enums.ActionStrategy.rotate => {
                return self.doRotate(allocator) catch |err| {
                    return utils.printError(allocator, err, .logs, "Error running logs service: {s}");
                };
            },
            enums.ActionStrategy.truncate => {
                return self.doTruncate() catch |err| {
                    return utils.printError(allocator, err, .logs, "Error running logs service: {s}");
                };
            },
        }
    }

    fn doRotate(self: LogService, allocator: Allocator) !void {
        std.log.scoped(.logs).info("Processing file rotations for path: {s}", .{self.directory});
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        std.log.debug("Matcher is: {s}", .{self.matcher});
        const files = try findRegexMatchesInDir(arena.allocator(), self.directory, self.matcher);
        std.log.debug("Matched files are: {any}", .{files.items});
        for (files.items) |file_name| {
            var paths = [_][]const u8{ self.directory, file_name };
            const path = std.fs.path.join(allocator, &paths) catch |err| {
                std.log.scoped(.logs).err("error joining paths: {s}/{s}, {}", .{ self.directory, file_name, err });
                continue;
            };
            defer allocator.free(path);

            if (shouldProcess(self.log_action.@"if".?, path, self.timezone)) {
                const rotation_file = std.fmt.allocPrint(allocator, "{s}-{d}", .{ file_name, datetime.Datetime.now().toTimestamp() }) catch |err| {
                    std.log.scoped(.logs).err("error generating file name for {s}: {}", .{ path, err });
                    continue;
                };
                defer allocator.free(rotation_file);

                var rotation_paths = [_][]const u8{ self.log_action.rotate_archives_dir.?, rotation_file };
                const rotation_path = std.fs.path.join(allocator, &rotation_paths) catch |err| {
                    std.log.scoped(.logs).err("error joining paths: {s}/{s}, {}", .{ self.log_action.rotate_archives_dir.?, rotation_file, err });
                    continue;
                };
                defer allocator.free(rotation_path);

                _ = std.fs.openDirAbsolute(self.log_action.rotate_archives_dir.?, .{}) catch |err| {
                    if (err == std.fs.Dir.OpenError.FileNotFound) {
                        std.fs.makeDirAbsolute(self.log_action.rotate_archives_dir.?) catch {
                            std.log.scoped(.log).err("unable to create rotate directory {s}: {}", .{ self.log_action.rotate_archives_dir.?, err });
                            continue;
                        };
                    } else {
                        std.log.scoped(.log).err("unable to create rotate directory {s}: {}", .{ self.log_action.rotate_archives_dir.?, err });
                        continue;
                    }
                };

                std.fs.renameAbsolute(path, rotation_path) catch |err| {
                    std.log.scoped(.log).err("unable to rotate file {s} -> {s}: {}", .{ path, rotation_path, err });
                    continue;
                };
                std.log.scoped(.logs).info("file rotated from {s} to {s}", .{ path, rotation_path });

                if (self.log_action.compress != null)
                    compressAndRotate(allocator, self.log_action, rotation_path) catch |err| {
                        std.log.scoped(.logs).err("Error compression file {s}: {}", .{ rotation_path, err });
                        continue;
                    };

                if (self.log_action.keep_archive != null) {
                    const pruner = self.getPruner(arena.allocator()) catch |err| {
                        std.log.scoped(.log).err("unable to create a pruner for archive file in {s}: {}", .{ self.log_action.rotate_archives_dir.?, err });
                        continue;
                    };

                    pruner.runAndDestroy();
                }
            }
        }
    }

    fn doDelete(self: LogService, allocator: Allocator) !void {
        std.log.scoped(.logs).info("Processing file deletions for path: {s}", .{self.directory});
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        std.log.debug("Matcher is: {s}", .{self.matcher});
        const files = try findRegexMatchesInDir(arena.allocator(), self.directory, self.matcher);
        std.log.debug("Matched files are: {any}", .{files.items});

        for (files.items) |file_name| {
            var paths = [_][]const u8{ self.directory, file_name };
            const path = std.fs.path.join(allocator, &paths) catch |err| {
                std.log.scoped(.logs).err("error joining paths: {s}/{s}, {}", .{ self.directory, file_name, err });
                continue;
            };
            defer allocator.free(path);

            if (shouldProcess(self.log_action.@"if".?, path, self.timezone)) {
                std.fs.deleteFileAbsolute(path) catch |err| {
                    std.log.scoped(.log).err("unable to delete file {s}: {}", .{ path, err });
                    continue;
                };
                std.log.scoped(.logs).info("deleted file: {s}", .{file_name});
            }
        }
    }

    fn doTruncate(self: LogService) !void {
        switch (std.meta.stringToEnum(enums.TruncateFrom, self.log_action.truncate_settings.?.from.?) orelse return TaseNativeErrors.InvalidTruncateFromFieldValue) {
            .bottom => {
                return self.truncateFromBottom();
            },
            .top => {
                return self.truncateFromTop();
            },
        }
    }

    fn truncateFromBottom(_: LogService) void {}

    fn truncateFromTop(_: LogService) void {}

    fn getPruner(self: LogService, allocator: Allocator) !*LogService {
        var matcher = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ self.matcher, "[0-9]+" });

        if (self.log_action.compress != null) {
            const compress_type = std.meta.stringToEnum(enums.CompressType, self.log_action.compress.?) orelse return TaseNativeErrors.InvalidCompressionType;
            matcher = try std.fmt.allocPrint(allocator, "{s}-{s}\\.{s}", .{ self.matcher, "[0-9]+", compress_type.getCompressionExtension() });
        }

        const log_action = configs.LogAction{
            .strategy = enums.ActionStrategy.delete.str(),
            .@"if" = self.log_action.keep_archive,
        };

        return LogService.create(
            allocator,
            self.timezone.*,
            self.log_action.rotate_archives_dir.?,
            matcher,
            log_action,
        );
    }
};

fn shouldProcess(ifOpr: configs.IfOperation, path: []u8, timezone: *datetime.Timezone) bool {
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

fn compressAndRotate(allocator: Allocator, log_action: *configs.LogAction, path: []const u8) !void {
    const compress_type = std.meta.stringToEnum(enums.CompressType, log_action.compress.?) orelse return TaseNativeErrors.InvalidCompressionType;

    const rotation_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ path, compress_type.getCompressionExtension() });
    defer allocator.free(rotation_path);

    var writer = std.ArrayList(u8).init(allocator);
    defer writer.deinit();
    var reader = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer reader.close();

    const compressor = compressionFactory.getCompressor(compress_type);
    try compressor.compress(reader.reader(), writer.writer(), .{ .level = @enumFromInt(log_action.compression_level.?) });
    const rotated_file = try std.fs.createFileAbsolute(rotation_path, .{ .mode = 0o666 });

    defer rotated_file.close();
    _ = try rotated_file.write(writer.items);
    try std.fs.deleteFileAbsolute(path);
    std.log.scoped(.logs).info("file compressed from {s} to {s}", .{ path, rotation_path });
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
