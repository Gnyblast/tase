const std = @import("std");
const yaml = @import("yaml");
const argsParser = @import("args");
const timezones = @import("datetime").timezones;
const cron = @import("cron");

const configs = @import("./app/config.zig");
const app = @import("./app/tase.zig");
const logger = @import("./utils/logger.zig");
const errorFactory = @import("./factory/error_factory.zig");
const serverFactory = @import("./factory/server_factory.zig");
const Allocator = std.mem.Allocator;
const ErrorMessage = @import("./factory/error_factory.zig").ErrorMessage;

pub const std_options: std.Options = .{ .logFn = logFn, .log_level = .debug };

var log_level = std.log.default_level;
pub var log_path: []const u8 = ""; //? The logic for default log dir is in logger.zig getLogFilePath()
pub var is_agent: bool = false;
pub var timezone: []const u8 = "UTC";

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) <= @intFromEnum(log_level)) {
        var tz = timezones.getByName(timezone) catch timezones.UTC;
        logger.log(
            message_level,
            scope,
            format,
            log_path,
            is_agent,
            args,
            &tz,
            log_level,
        );
    }
}

pub fn main() void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer {
        const leaks = da.deinit();
        std.debug.assert(leaks == .ok);
    }

    const allocator = da.allocator();
    const cli_args = parseCLIOrExit(allocator);
    defer cli_args.deinit();

    var tase = app.Tase.init(allocator, &cli_args.options) catch |err| {
        const err_msg = errorFactory.getLogMessageByErr(allocator, err);
        defer if (err_msg.allocated) allocator.free(err_msg.message);
        std.debug.print("Check logs for more details at: {s}", .{cli_args.options.@"log-dir"});
        std.log.scoped(.yaml).err("Could not create application: {s}", .{err_msg.message});
        std.process.exit(1);
    };
    defer tase.deinit();
    timezone = tase.yaml_cfg.server.time_zone.?;

    tase.run() catch |err| {
        const err_msg = errorFactory.getLogMessageByErr(allocator, err);
        defer if (err_msg.allocated) allocator.free(err_msg.message);
        std.debug.print("Check logs for more details at: {s}", .{tase.cli_args.@"log-dir"});
        std.log.err("Could not start application: {s}", .{err_msg.message});
        std.process.exit(1);
    };
}

fn parseCLIOrExit(allocator: Allocator) argsParser.ParseArgsResult(configs.argOpts, null) {
    const cli_args = argsParser.parseForCurrentProcess(configs.argOpts, allocator, .print) catch |err| {
        std.debug.print("Error parsing CLI arguments: {}", .{err});
        std.process.exit(1);
    };
    //? Do not log anything into std.log before below lines.
    log_level = cli_args.options.@"log-level";
    log_path = cli_args.options.@"log-dir";
    is_agent = cli_args.options.agent;

    if (cli_args.options.help) {
        argsParser.printHelp(configs.argOpts, "Tase", std.io.getStdOut().writer()) catch |err| {
            std.log.err("Could not print help: {}", .{err});
        };
        std.process.exit(0);
    }

    std.log.debug("parsed options:", .{});
    inline for (std.meta.fields(@TypeOf(cli_args.options))) |fld| {
        std.log.debug("\t\t{s} = {any}", .{
            fld.name,
            @field(cli_args.options, fld.name),
        });
    }

    return cli_args;
}
