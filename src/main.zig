const std = @import("std");
const yaml = @import("yaml");
const configs = @import("./app/config.zig");
const checks = @import("./app/checks.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();

    // Read contents from file "./filename"
    const cwd = std.fs.cwd();
    const fileContents = try cwd.readFileAlloc(allocator, "./config.yaml", 4096);
    defer allocator.free(fileContents);

    var typed = try yaml.Yaml.load(allocator, fileContents);
    defer typed.deinit();

    var tesa = configs.Tesa.init(allocator);
    defer tesa.deinit();

    const confWrapper = struct { configs: []configs.LogConf };

    const confs = try typed.parse(confWrapper);
    for (confs.configs) |c| {
        try tesa.AddConf(c);
    }
    std.debug.print("{s}\n", .{tesa.configs.items[0].app_name});
    checks.doInitialChecks(tesa.configs) catch |err| {
        std.debug.print("{any}", .{err});
        std.process.exit(1);
    };
}
