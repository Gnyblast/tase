const std = @import("std");
const yaml = @import("yaml");

const configs = @import("./cli/config.zig");
const app = @import("./cli/tase.zig");
const parser = @import("./utils/parser.zig");
const logger = @import("./utils/logger.zig");

pub const std_options: std.Options = .{ .logFn = logger.log, .log_level = .info };

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    std.log.info("{s}:{d} parsing config file at {s}", .{ @src().fn_name, @src().line, ".config.yaml" });
    const cwd = std.fs.cwd();
    const fileContents = cwd.readFileAlloc(allocator, "./config.yaml", 4096) catch |err| {
        std.log.err("{s}:{d} could not locate config (yaml) file: {}", .{ @src().fn_name, @src().line, err });
        std.process.exit(1);
    };

    std.log.info("{s}:{d} loading conf file content", .{ @src().fn_name, @src().line });
    var typed = yaml.Yaml.load(arena_alloc, fileContents) catch |err| {
        std.log.err("{s}:{d} error loading file contents: {}", .{ @src().fn_name, @src().line, err });
        std.process.exit(1);
    };
    defer typed.deinit();

    std.log.info("{s}:{d} loading conf to struct", .{ @src().fn_name, @src().line });
    const confs = typed.parse(struct { configs: []configs.LogConf }) catch |err| {
        std.log.err("{s}:{d} error parsing into struct: {}", .{ @src().fn_name, @src().line, err });
        std.process.exit(1);
    };
    allocator.free(fileContents);

    var tase = app.Tase.init(allocator);
    defer tase.deinit();

    const cli_args = parser.parseCLI(allocator) catch |err| {
        std.log.err("{s}:{d} error parsing CLI arguments: {}", .{ @src().fn_name, @src().line, err });
        std.process.exit(1);
    };
    tase.cli_args = cli_args.options;
    cli_args.deinit();

    for (confs.configs) |c| {
        tase.addConf(c) catch |err| {
            std.log.err("{s}:{d} could not add the config to app: {}", .{ @src().fn_name, @src().line, err });
            std.process.exit(1);
        };
    }

    tase.run() catch |err| {
        std.log.err("{s}:{d} could not start application: {}", .{ @src().fn_name, @src().line, err });
        std.process.exit(1);
    };
}
