const std = @import("std");
const testing = std.testing;
const datetime = @import("datetime").datetime;
const configs = @import("../app/config.zig");
const enums = @import("../enum/config_enum.zig");

const helper = @import("prune_helper.zig");
const Pruner = @import("./pruner.zig").Pruner;

const Allocator = std.mem.Allocator;

pub fn doDelete(pruner: Pruner, allocator: Allocator) !void {
    std.log.scoped(.logs).info("Processing file deletions for path: {s}", .{pruner.directory});
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
            std.fs.deleteFileAbsolute(path) catch |err| {
                std.log.scoped(.log).err("unable to delete file {s}: {any}", .{ path, err });
                continue;
            };
            std.log.scoped(.logs).info("deleted file: {s}", .{file_name});
        }
    }
}

test "doDeleteTest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var tz = datetime.timezones.Asia.Nicosia;
    var log_action = configs.LogAction{
        .strategy = enums.ActionStrategy.delete.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
    };
    var log_action_not_process = configs.LogAction{
        .strategy = enums.ActionStrategy.delete.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = ">",
            .operand = 10,
        },
    };
    var log_action_equal = configs.LogAction{
        .strategy = enums.ActionStrategy.delete.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "=",
            .operand = 10,
        },
    };
    var log_action_by_age_gt = configs.LogAction{
        .strategy = enums.ActionStrategy.delete.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.days.str(),
            .operator = ">",
            .operand = 10,
        },
    };
    var log_action_by_age_lt = configs.LogAction{
        .strategy = enums.ActionStrategy.delete.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.days.str(),
            .operator = "<",
            .operand = 10,
        },
    };
    var log_action_by_age_eq = configs.LogAction{
        .strategy = enums.ActionStrategy.delete.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.days.str(),
            .operator = "=",
            .operand = 10,
        },
    };

    const TestCase = struct {
        log_action: *configs.LogAction,
        matcher: []const u8,
    };
    var tcs = [_]TestCase{
        .{
            .log_action = &log_action,
            .matcher = "mock-delete.*",
        },
        .{
            .log_action = &log_action_not_process,
            .matcher = "mock-delete.*",
        },
        .{
            .log_action = &log_action_equal,
            .matcher = "mock-delete.*",
        },
        .{
            .log_action = &log_action_by_age_gt,
            .matcher = "mock-delete.*",
        },
        .{
            .log_action = &log_action_by_age_lt,
            .matcher = "mock-delete.*",
        },
        .{
            .log_action = &log_action_by_age_eq,
            .matcher = "mock-delete.*",
        },
    };

    const cwd = try std.fs.realpathAlloc(testing.allocator, "./test/unit-test-dir");
    defer testing.allocator.free(cwd);

    for (&tcs) |tc| {
        var paths = [_][]const u8{ cwd, "mock-delete.log" };
        const mock_file_path = try std.fs.path.join(testing.allocator, &paths);
        defer testing.allocator.free(mock_file_path);
        var mock_file = try std.fs.createFileAbsolute(mock_file_path, .{});
        defer mock_file.close();
        defer std.fs.deleteFileAbsolute(mock_file_path) catch {};

        const pruner = Pruner.init(
            arena,
            &tz,
            cwd,
            tc.matcher,
            tc.log_action,
        );

        try doDelete(pruner, testing.allocator);
    }
}
