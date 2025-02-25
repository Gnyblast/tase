const std = @import("std");

const Allocator = std.mem.Allocator;

const checks = @import("../utils/checks.zig");
const configs = @import("./config.zig");

pub const Tase = struct {
    configs: std.ArrayList(configs.LogConf),
    cli_args: ?configs.argOpts = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Tase {
        const arr_list = std.ArrayList(configs.LogConf).init(allocator);
        return Tase{
            .allocator = allocator,
            .configs = arr_list,
            .cli_args = null,
        };
    }

    pub fn run(self: *Tase) void {
        std.log.info("doing initial value checks", .{});
        checks.doInitialChecks(self.configs) catch |err| {
            std.log.err("failed to confirm config values: {}", .{err});
            std.process.exit(1);
        };
        //TODO run logic here
    }

    pub fn addConf(self: *Tase, conf: configs.LogConf) !void {
        try self.configs.append(conf);
    }

    pub fn deinit(self: *Tase) void {
        self.configs.deinit();
    }
};
