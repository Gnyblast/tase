const std = @import("std");
const datetime = @import("datetime").datetime;

const configs = @import("../app/config.zig");
const enums = @import("../enum/config_enum.zig");
const fileMatcher = @import("./file_matcher_service.zig");

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
            enums.ActionStrategy.rotate => return self.doRotate(),
            enums.ActionStrategy.truncate => return self.doTruncate(),
        }
    }

    fn doRotate(_: LogService) !void {}

    fn doDelete(self: LogService, allocator: Allocator) !void {
        std.log.info("Processing file deletions for path: {s}", .{self.directory});
        var arena = std.heap.ArenaAllocator.init(allocator);
        const files = try fileMatcher.findRegexMatchesInDir(arena.allocator(), self.directory, self.matcher);
        defer arena.deinit();

        for (files.items) |file_name| {
            var paths = [_][]const u8{ self.directory, file_name };
            const path = std.fs.path.join(allocator, &paths) catch |err| {
                std.log.scoped(.logs).err("error joining paths: {s}/{s}, {}", .{ self.directory, file_name, err });
                continue;
            };
            defer allocator.free(path);

            const file = std.fs.openFileAbsolute(path, .{ .mode = .read_write }) catch |err| {
                std.log.scoped(.logs).err("error opening file: {s} {}", .{ path, err });
                continue;
            };
            defer file.close();

            const file_stats = file.metadata() catch |err| {
                std.log.scoped(.logs).err("error retrieving file metadata: {s} {}", .{ path, err });
                continue;
            };

            const mtime_ns = file_stats.modified();

            const mtime_ms: i64 = @as(i64, @intCast(@divFloor(mtime_ns, std.time.ns_per_ms)));

            const modification = datetime.Datetime.fromTimestamp(mtime_ms).shiftTimezone(&self.timezone);
            const now = datetime.Datetime.now().shiftTimezone(&self.timezone).shiftDays(-self.log_action.delete_older_than_days.?);
            if (now.cmp(modification) == .gt) {
                std.log.scoped(.logs).info("deleting file: {s}", .{file_name});
                try std.fs.deleteFileAbsolute(path);
            }
        }
    }

    fn doTruncate(_: LogService) !void {}
};
