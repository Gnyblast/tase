const std = @import("std");

const Allocator = std.mem.Allocator;

const configs = @import("./config.zig");
const helpers = @import("../utils/helper.zig");

pub const version = "0.0.1";

pub const Tase = struct {
    yamlCfg: ?configs.YamlCfgContainer = null,
    cli_args: ?configs.argOpts = null,
    comptime version: []const u8 = version,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Tase {
        return Tase{
            .allocator = allocator,
            .cli_args = null,
            .yamlCfg = null,
        };
    }

    pub fn run(self: *Tase) !void {
        std.log.debug("Doing initial value checks", .{});
        try self.yamlCfg.?.isValidYaml(self.allocator);
        if (!self.cli_args.?.master and !self.cli_args.?.slave) {
            return error.ServerMustStartedEitherAsMasterOrSlave;
        }
        if (self.cli_args.?.master and self.cli_args.?.slave) {
            return error.ServerCannotBeStartedBothAsMasterAndSlave;
        }
        helpers.printApplicationInfo(self.version);
    }

    // pub fn addConf(self: *Tase, conf: configs.LogConf) !void {
    //     try self.configs.append(conf);
    // }
};
