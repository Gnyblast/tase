const std = @import("std");
const testing = std.testing;
const datetime = @import("datetime").datetime;
const helper = @import("prune_helper.zig");
const configs = @import("../app/config.zig");
const enums = @import("../enum/config_enum.zig");
const compressionFactory = @import("../factory/compression_factory.zig");
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;
const Pruner = @import("./pruner.zig").Pruner;

const Allocator = std.mem.Allocator;

pub fn doRotate(pruner: Pruner, allocator: Allocator) !void {
    std.log.scoped(.logs).info("Processing file rotations for path: {s}", .{pruner.directory});
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
            const rotation_file = std.fmt.allocPrint(allocator, "{s}-{d}", .{ file_name, datetime.Datetime.now().toTimestamp() }) catch |err| {
                std.log.scoped(.logs).err("error generating file name for {s}: {any}", .{ path, err });
                continue;
            };
            defer allocator.free(rotation_file);

            var rotation_paths = [_][]const u8{ pruner.log_action.rotate_archives_dir.?, rotation_file };
            const rotation_path = std.fs.path.join(allocator, &rotation_paths) catch |err| {
                std.log.scoped(.logs).err("error joining paths: {s}/{s}, {any}", .{ pruner.log_action.rotate_archives_dir.?, rotation_file, err });
                continue;
            };
            defer allocator.free(rotation_path);

            _ = std.fs.openDirAbsolute(pruner.log_action.rotate_archives_dir.?, .{}) catch |err| {
                if (err == std.fs.Dir.OpenError.FileNotFound) {
                    std.fs.makeDirAbsolute(pruner.log_action.rotate_archives_dir.?) catch {
                        std.log.scoped(.log).err("unable to create rotate directory {s}: {any}", .{ pruner.log_action.rotate_archives_dir.?, err });
                        continue;
                    };
                } else {
                    std.log.scoped(.log).err("unable to create rotate directory {s}: {any}", .{ pruner.log_action.rotate_archives_dir.?, err });
                    continue;
                }
            };

            std.fs.renameAbsolute(path, rotation_path) catch |err| {
                std.log.scoped(.log).err("unable to rotate file {s} -> {s}: {any}", .{ path, rotation_path, err });
                continue;
            };
            std.log.scoped(.logs).info("file rotated from {s} to {s}", .{ path, rotation_path });

            if (pruner.log_action.compress != null)
                compressAndRotate(allocator, pruner.log_action, rotation_path) catch |err| {
                    std.log.scoped(.logs).err("Error compression file {s}: {any}", .{ rotation_path, err });
                    continue;
                };

            if (pruner.log_action.keep_archive != null) {
                const new_pruner = getPruner(pruner.log_action, pruner.matcher, pruner.timezone, arena.allocator()) catch |err| {
                    std.log.scoped(.log).err("unable to create a pruner for archive file in {s}: {any}", .{ pruner.log_action.rotate_archives_dir.?, err });
                    continue;
                };

                new_pruner.runAndDestroy();
            }
        }
    }
}

fn compressAndRotate(allocator: Allocator, log_action: *configs.LogAction, path: []const u8) !void {
    const compress_type = std.meta.stringToEnum(enums.CompressType, log_action.compress.?) orelse return TaseNativeErrors.InvalidCompressionType;

    const rotation_path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ path, compress_type.getCompressionExtension() });
    defer allocator.free(rotation_path);

    var writer = try std.fs.createFileAbsolute(rotation_path, .{ .mode = 0o666 });
    defer writer.close();
    var reader = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer reader.close();

    const compressor = compressionFactory.getCompressor(compress_type);
    try compressor.compress(reader, writer, log_action.compression_level.?);

    try std.fs.deleteFileAbsolute(path);
    std.log.scoped(.logs).info("file compressed from {s} to {s}", .{ path, rotation_path });
}

fn getPruner(base_log_action: *configs.LogAction, base_matcher: []const u8, timezone: *datetime.Timezone, allocator: Allocator) !*Pruner {
    var matcher = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ base_matcher, "[0-9]+" });

    if (base_log_action.compress != null) {
        const compress_type = std.meta.stringToEnum(enums.CompressType, base_log_action.compress.?) orelse return TaseNativeErrors.InvalidCompressionType;
        matcher = try std.fmt.allocPrint(allocator, "{s}-{s}\\.{s}", .{ base_matcher, "[0-9]+", compress_type.getCompressionExtension() });
    }

    const log_action = configs.LogAction{
        .strategy = enums.ActionStrategy.delete.str(),
        .@"if" = base_log_action.keep_archive,
    };

    return Pruner.create(
        allocator,
        timezone.*,
        base_log_action.rotate_archives_dir.?,
        matcher,
        log_action,
    );
}

test "doRotateTest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
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

    var log_action = configs.LogAction{
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

    const TestCase = struct {
        log_action: *configs.LogAction,
        matcher: []const u8,
    };
    var tcs = [_]TestCase{
        .{
            .log_action = &log_action,
            .matcher = "mock-rotate.*",
        },
    };

    for (&tcs) |tc| {
        var paths = [_][]const u8{ cwd, "mock-rotate.log" };
        const mock_file_path = try std.fs.path.join(testing.allocator, &paths);
        defer testing.allocator.free(mock_file_path);
        var mock_file = try std.fs.createFileAbsolute(mock_file_path, .{});
        defer mock_file.close();

        const pruner = Pruner.init(
            arena,
            &tz,
            cwd,
            tc.matcher,
            tc.log_action,
        );

        try doRotate(pruner, testing.allocator);
    }
}

test "compressAndRotateTest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const cwd = try std.fs.realpathAlloc(testing.allocator, "./test/unit-test-dir");
    var archive_paths = [_][]const u8{ cwd, "archives" };
    const mock_archive_path = try std.fs.path.join(testing.allocator, &archive_paths);
    try std.fs.makeDirAbsolute(mock_archive_path);
    defer {
        std.fs.deleteTreeAbsolute(mock_archive_path) catch |err| {
            std.debug.print("{any}", .{err});
        };
        testing.allocator.free(mock_archive_path);
        testing.allocator.free(cwd);
    }

    var log_action = configs.LogAction{
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

    var paths = [_][]const u8{ mock_archive_path, "mock-rotate.log" };
    const mock_file_path = try std.fs.path.join(testing.allocator, &paths);
    defer testing.allocator.free(mock_file_path);
    var mock_file = try std.fs.createFileAbsolute(mock_file_path, .{});
    defer mock_file.close();
    try compressAndRotate(arena.allocator(), &log_action, mock_file_path);
}

test "getPrunerTest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
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

    var log_action = configs.LogAction{
        .strategy = enums.ActionStrategy.rotate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
        .rotate_archives_dir = mock_archive_path,
        .compress = enums.CompressType.gzip.str(),
        .keep_archive = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
    };

    var log_action_no_compress = configs.LogAction{
        .strategy = enums.ActionStrategy.rotate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
        .rotate_archives_dir = mock_archive_path,
        .keep_archive = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
    };

    var log_action_err = configs.LogAction{
        .strategy = enums.ActionStrategy.rotate.str(),
        .@"if" = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
        .rotate_archives_dir = mock_archive_path,
        .compress = "test",
        .keep_archive = configs.IfOperation{
            .condition = enums.IfConditions.size.str(),
            .operator = "<",
            .operand = 10,
        },
    };

    const TestCase = struct {
        log_action: *configs.LogAction,
        err: ?anyerror = null,
    };
    var tcs = [_]TestCase{
        .{
            .log_action = &log_action,
        },
        .{
            .log_action = &log_action_no_compress,
        },
        .{
            .log_action = &log_action_err,
            .err = TaseNativeErrors.InvalidCompressionType,
        },
    };

    for (&tcs) |tc| {
        if (tc.err != null)
            try testing.expectError(tc.err.?, getPruner(tc.log_action, "mock-rorate.*", &tz, arena.allocator()))
        else
            _ = try getPruner(
                tc.log_action,
                "mock-rorate.*",
                &tz,
                arena.allocator(),
            );
    }
}
