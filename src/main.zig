const std = @import("std");
const argsParser = @import("args");
const timezones = @import("datetime").timezones;

const configs = @import("./app/config.zig");
const utils = @import("./utils/helper.zig");
const app = @import("./app/tase.zig");
const logger = @import("./utils/logger.zig");

const Allocator = std.mem.Allocator;

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
        const tz = timezones.getByName(timezone) catch timezones.UTC;
        logger.log(
            message_level,
            scope,
            format,
            log_path,
            is_agent,
            args,
            tz,
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
        return utils.printErrorExit(allocator, err, cli_args.options, .yaml, "Could not create application: {s}");
    };
    defer tase.deinit();
    timezone = tase.yaml_cfg.server.time_zone.?;

    tase.run() catch |err| {
        return utils.printErrorExit(allocator, err, tase.cli_args.*, .default, "Could not start application: {s}");
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
