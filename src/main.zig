const std = @import("std");
const yaml = @import("yaml");
const argsParser = @import("args");
const cron = @import("cron");

const configs = @import("./app/config.zig");
const app = @import("./app/tase.zig");
const logger = @import("./utils/logger.zig");
const Allocator = std.mem.Allocator;

pub const std_options: std.Options = .{ .logFn = logFn, .log_level = .debug };
pub const scope_levels = [_]std.log.ScopeLevel{
    .{ .scope = .parse, .level = .info },
    .{ .scope = .tokenizer, .level = .info },
};

var log_level = std.log.default_level;
pub var log_path: []const u8 = ""; //? The logic for default log dir is in logger.zig getLogFilePath()

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) <= @intFromEnum(log_level)) {
        logger.log(message_level, scope, format, log_path, args);
    }
}

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const cli_args = argsParser.parseForCurrentProcess(configs.argOpts, allocator, .print) catch |err| {
        std.debug.print("Error parsing CLI arguments: {}", .{err});
        std.process.exit(1);
    };
    log_level = cli_args.options.@"logs-level";
    log_path = cli_args.options.@"logs-path";
    std.log.info("CLI argument: --logs-path: {s} --logs-level: {} --master: {} --slave: {}", .{ cli_args.options.@"logs-path", cli_args.options.@"logs-level", cli_args.options.master, cli_args.options.slave });

    var tase = app.Tase.init(allocator);
    tase.cli_args = cli_args.options;

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    std.log.debug("Parsing config file at {s}", .{tase.cli_args.?.config});
    const cwd = std.fs.cwd();
    const fileContents = cwd.readFileAlloc(allocator, tase.cli_args.?.config, 4096) catch |err| {
        std.log.err("Could not locate config (yaml) file: {}", .{err});
        std.process.exit(1);
    };

    std.log.debug("Loading conf file content", .{});
    var typed = yaml.Yaml.load(arena_alloc, fileContents) catch |err| {
        std.log.err("Error loading file contents: {}", .{err});
        std.process.exit(1);
    };
    defer typed.deinit();

    std.log.debug("Loading conf to struct", .{});
    tase.yamlCfg = typed.parse(configs.YamlCfgContainer) catch |err| {
        std.log.err("Error parsing into struct: {}", .{err});
        std.process.exit(1);
    };
    allocator.free(fileContents);
    cli_args.deinit();

    tase.run() catch |err| {
        std.debug.print("Check logs for more details at: {s}", .{cli_args.options.@"logs-path"});
        std.log.err("Could not start application: {}", .{err});
        std.process.exit(1);
    };
}
