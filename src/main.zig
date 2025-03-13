const std = @import("std");
const yaml = @import("yaml");
const argsParser = @import("args");
const cron = @import("cron");

const configs = @import("./app/config.zig");
const app = @import("./app/tase.zig");
const logger = @import("./utils/logger.zig");
const errorFactory = @import("./factory/error_factory.zig");
const serverFactory = @import("./factory/server_factory.zig");
const Allocator = std.mem.Allocator;

pub const std_options: std.Options = .{ .logFn = logFn, .log_level = .debug };

var log_level = std.log.default_level;
pub var log_path: []const u8 = ""; //? The logic for default log dir is in logger.zig getLogFilePath()
pub var is_agent: bool = false;

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) <= @intFromEnum(log_level)) {
        logger.log(message_level, scope, format, log_path, is_agent, args);
    }
}

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const cli_args = parseCLIOrExit(allocator);
    defer cli_args.deinit();

    var loaded_yaml = loadYAMLFileOrExit(allocator, cli_args.options.config);
    defer loaded_yaml.deinit(allocator);

    var yaml_cfg: configs.YamlCfgContainer = undefined;

    if (cli_args.options.master) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        yaml_cfg = parseYAMLOrExit(&arena, &loaded_yaml);
    }

    var tase = app.Tase.init(allocator, &cli_args.options, &yaml_cfg) catch |err| {
        const err_msg = errorFactory.getLogMessageByErr(allocator, err);
        defer allocator.free(err_msg);
        std.debug.print("Check logs for more details at: {s}", .{cli_args.options.@"log-dir"});
        std.log.scoped(.yaml).err("Could not create application: {s}", .{err_msg});
        std.process.exit(1);
    };
    defer tase.deinit();

    tase.run() catch |err| {
        const err_msg = errorFactory.getLogMessageByErr(allocator, err);
        defer allocator.free(err_msg);
        std.debug.print("Check logs for more details at: {s}", .{tase.cli_args.@"log-dir"});
        std.log.err("Could not start application: {s}", .{err_msg});
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

fn loadYAMLFileOrExit(allocator: Allocator, file_path: []const u8) yaml.Yaml {
    std.log.debug("Parsing config file at {s}", .{file_path});
    const cwd = std.fs.cwd();
    const fileContents = cwd.readFileAlloc(allocator, file_path, 4096) catch |err| {
        std.log.scoped(.yaml).err("Could not locate config (yaml) file: {}", .{err});
        std.process.exit(1);
    };
    defer allocator.free(fileContents);

    std.log.debug("Loading conf file content", .{});
    return yaml.Yaml.load(allocator, fileContents) catch |err| {
        std.log.scoped(.yaml).err("Error loading file contents: {}", .{err});
        std.process.exit(1);
    };
}

fn parseYAMLOrExit(arena: *std.heap.ArenaAllocator, loaded: *yaml.Yaml) configs.YamlCfgContainer {
    const alloc = arena.allocator();
    std.log.debug("Loading conf to struct", .{});
    return loaded.parse(alloc, configs.YamlCfgContainer) catch |err| {
        std.log.scoped(.yaml).err("Error parsing into struct: {}", .{err});
        std.process.exit(1);
    };
}
