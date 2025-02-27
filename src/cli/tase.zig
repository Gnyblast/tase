const std = @import("std");

const Allocator = std.mem.Allocator;

const configs = @import("./config.zig");
const helpers = @import("../utils/helper.zig");

pub const Tase = struct {
    configs: std.ArrayList(configs.LogConf),
    cli_args: ?configs.argOpts = null,
    comptime version: []const u8 = "0.0.1",
    allocator: Allocator,

    pub fn init(allocator: Allocator) Tase {
        const arr_list = std.ArrayList(configs.LogConf).init(allocator);
        return Tase{
            .allocator = allocator,
            .configs = arr_list,
            .cli_args = null,
        };
    }

    pub fn run(self: *Tase) !void {
        std.log.debug("Doing initial value checks", .{});
        for (self.configs.items) |cfg| {
            try cfg.configValid();
        }
        helpers.printApplicationInfo(self.version);
    }

    pub fn addConf(self: *Tase, conf: configs.LogConf) !void {
        try self.configs.append(conf);
    }

    pub fn deinit(self: *Tase) void {
        self.configs.deinit();
    }
};
