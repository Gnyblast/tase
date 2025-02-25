const std = @import("std");
const yaml = @import("yaml");

const configs = @import("./cli/config.zig");
const app = @import("./cli/tase.zig");
const parser = @import("./utils/parser.zig");
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

    std.log.info("loading conf to struct", .{});
    const confs = typed.parse(struct { configs: []configs.LogConf }) catch |err| {
        std.log.err("error parsing into struct: {}", .{err});
        std.process.exit(1);
    };
    allocator.free(fileContents);

    var tase = app.Tase.init(allocator);
    defer tase.deinit();

    const cli_args = parser.parseCLI(allocator) catch |err| {
        std.log.err("error parsing CLI arguments: {}", .{err});
        std.process.exit(1);
    };
    tase.cli_args = cli_args.options;
    cli_args.deinit();

    for (confs.configs) |c| {
        tase.addConf(c) catch |err| {
            std.log.err("could not add the config to app: {}", .{err});
            std.process.exit(1);
        };
    }

    tase.run();
}
