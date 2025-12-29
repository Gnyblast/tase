const std = @import("std");
const testing = std.testing;
const datetime = @import("datetime").datetime;

const configs = @import("../app/config.zig");
const utils = @import("../utils/helper.zig");
const enums = @import("../enum/config_enum.zig");
const compressionFactory = @import("../factory/compression_factory.zig");
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;
const doDelete = @import("./delete_service.zig").doDelete;
const doRotate = @import("./rotate_service.zig").doRotate;
const doTruncate = @import("truncate_service.zig").doTruncate;

pub const Pruner = struct {
    arena: ?Arena,
    timezone: *datetime.Timezone,
    directory: []const u8,
    matcher: []const u8,
    log_action: *configs.LogAction,

    pub fn init(arena: ?Arena, timezone: *datetime.Timezone, directory: []const u8, matcher: []const u8, log_action: *configs.LogAction) Pruner {
        return Pruner{
            .arena = arena,
            .timezone = timezone,
            .directory = directory,
            .matcher = matcher,
            .log_action = log_action,
        };
    }

    /// Using this method means you need to use runAndDestroy afterwards. Creates arena from the allocator and
    /// free everything at the end of runAndDestroy
    pub fn create(allocator: Allocator, timezone: datetime.Timezone, directory: []const u8, matcher: []const u8, log_action: configs.LogAction) !*Pruner {
        var arena = Arena.init(allocator);
        var aa = arena.allocator();

        const log_service = try aa.create(Pruner);
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
    pub fn runAndDestroy(self: *Pruner) void {
        defer {
            if (self.arena != null)
                self.arena.?.deinit();
        }
        self.run();
    }

    pub fn run(self: Pruner) void {
        var da: std.heap.DebugAllocator(.{}) = .init;
        defer {
            const leaks = da.deinit();
            std.debug.assert(leaks == .ok);
        }

        const allocator = da.allocator();

        self.log_action.checkActionValidity() catch |err| {
            return utils.printError(allocator, err, .logs, "Error running pruner: {s}");
        };

        switch (std.meta.stringToEnum(enums.ActionStrategy, self.log_action.strategy) orelse {
            std.log.scoped(.logs).err("Invalid Strategy {s}", .{self.log_action.strategy});
            return;
        }) {
            enums.ActionStrategy.delete => {
                return doDelete(self, allocator) catch |err| {
                    return utils.printError(allocator, err, .logs, "Error running pruner: {s}");
                };
            },
            enums.ActionStrategy.rotate => {
                return doRotate(self, allocator) catch |err| {
                    return utils.printError(allocator, err, .logs, "Error running pruner: {s}");
                };
            },
            enums.ActionStrategy.truncate => {
                return doTruncate(self, allocator) catch |err| {
                    return utils.printError(allocator, err, .logs, "Error running pruner: {s}");
                };
            },
        }
    }
};

test "initRunTest" {
    var arena = Arena.init(testing.allocator);
    defer arena.deinit();
    var tz = datetime.timezones.Asia.Nicosia;
    const cwd = try std.fs.realpathAlloc(testing.allocator, "./test/unit-test-dir");
    var archive_paths = [_][]const u8{ cwd, "archives" };
    const mock_archive_path = try std.fs.path.join(testing.allocator, &archive_paths);
    defer {
        std.fs.deleteTreeAbsolute(mock_archive_path) catch |err| {
            std.debug.print("{any}", .{err});
        };
        testing.allocator.free(mock_archive_path);
        testing.allocator.free(cwd);
    }

    var log_action_delete = configs.LogAction{
        .strategy = enums.ActionStrategy.delete.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
    };

    var log_action_rotate = configs.LogAction{
        .strategy = enums.ActionStrategy.rotate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
        .rotate_archives_dir = mock_archive_path,
        .compress = "gzip",
        .keep_archive = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
    };

    var log_action_truncate = configs.LogAction{
        .strategy = enums.ActionStrategy.truncate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
        .truncate_settings = configs.TruncateSettings{
            .from = enums.TruncateFrom.bottom.str(),
            .size = 10,
            .action = enums.TruncateAction.delete.str(),
            .by = enums.TruncateBy.line.str(),
        },
    };

    var missing_fields_validity_check = configs.LogAction{
        .strategy = enums.ActionStrategy.truncate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
    };

    var invalid_strategy = configs.LogAction{
        .strategy = "test",
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
    };

    const TestCase = struct {
        log_action: *configs.LogAction,
        path: []const u8,
    };
    var tcs = [_]TestCase{
        .{
            .log_action = &log_action_delete,
            .path = cwd,
        },
        .{
            .log_action = &log_action_delete,
            .path = "/invalid/dir",
        },
        .{
            .log_action = &log_action_rotate,
            .path = cwd,
        },
        .{
            .log_action = &log_action_rotate,
            .path = "/invalid/dir",
        },
        .{
            .log_action = &log_action_truncate,
            .path = cwd,
        },
        .{
            .log_action = &log_action_truncate,
            .path = "/invalid/dir",
        },
        .{
            .log_action = &missing_fields_validity_check,
            .path = cwd,
        },
        .{
            .log_action = &invalid_strategy,
            .path = cwd,
        },
    };

    for (&tcs) |tc| {
        const pruner = Pruner.init(arena, &tz, tc.path, "mock-test.log", tc.log_action);
        pruner.run();
    }
}

test "createRunDestoryTest" {
    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    const log_action = configs.LogAction{
        .strategy = enums.ActionStrategy.delete.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
    };
    const cwd = try std.fs.realpathAlloc(testing.allocator, "./test/unit-test-dir");
    defer testing.allocator.free(cwd);
    const pruner = try Pruner.create(arena.allocator(), datetime.timezones.Asia.Nicosia, cwd, "mock-test.log", log_action);
    pruner.runAndDestroy();
}
