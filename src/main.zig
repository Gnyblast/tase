const std = @import("std");
const yaml = @import("yaml");

const configs = @import("./app/config.zig");
const checks = @import("./app/checks.zig");
const parser = @import("./app/parser.zig");
const root = @import("root.zig");

pub const std_options = .{ .logFn = root.log, .log_level = .info };

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    std.log.info("parsing config file at {s}", .{".config.yaml"});
    const cwd = std.fs.cwd();
    const fileContents = cwd.readFileAlloc(allocator, "./config.yaml", 4096) catch |err| {
        std.log.err("could not locate config (yaml) file: {}", .{err});
        std.process.exit(1);
    };

    std.log.info("loading conf file content", .{});
    var typed = yaml.Yaml.load(arena_alloc, fileContents) catch |err| {
        std.log.err("error loading file contents: {}", .{err});
        std.process.exit(1);
    };
    defer typed.deinit();

    const confWrapper = struct { configs: []configs.LogConf };

    std.log.info("loading conf to struct", .{});
    const confs = typed.parse(confWrapper) catch |err| {
        std.log.err("error parsing into struct: {}", .{err});
        std.process.exit(1);
    };
    allocator.free(fileContents);

    var tesa = configs.Tesa.init(allocator);
    defer tesa.deinit();

    const cli_args = parser.parseCLI(allocator) catch |err| {
        std.log.err("error parsing CLI arguments: {}", .{err});
        std.process.exit(1);
    };
    tesa.cli_args = cli_args.options;
    cli_args.deinit();

    for (confs.configs) |c| {
        tesa.AddConf(c) catch |err| {
            std.log.err("could not add the config to app: {}", .{err});
            std.process.exit(1);
        };
    }

    std.log.info("doing initial value checks", .{});
    checks.doInitialChecks(tesa.configs) catch |err| {
        std.log.err("failed to confirm config values: {}", .{err});
        std.process.exit(1);
    };
}
