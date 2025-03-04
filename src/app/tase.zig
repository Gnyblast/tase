const std = @import("std");

const Allocator = std.mem.Allocator;

const configs = @import("./config.zig");
const helpers = @import("../utils/helper.zig");
const serverFactory = @import("../server/server_factory.zig");

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

        if (!self.cli_args.?.master and !self.cli_args.?.agent) {
            return error.ServerMustStartedEitherAsMasterOrSlave;
        }
        if (self.cli_args.?.master and self.cli_args.?.agent) {
            return error.ServerCannotBeStartedBothAsMasterAndSlave;
        }
        if (self.cli_args.?.agent and self.cli_args.?.secret == null) {
            return error.SecretIsMandatoryForAgents;
        }

        helpers.printApplicationInfo(self.version);
        var server: serverFactory.Server = undefined;
        if (self.cli_args.?.agent) {
            server = try serverFactory.getServer(self.cli_args.?.@"server-type", self.cli_args.?.host, self.cli_args.?.port, self.cli_args.?.secret);
        } else {
            server = try serverFactory.getServer(self.yamlCfg.?.server.type, self.yamlCfg.?.server.host, self.yamlCfg.?.server.port, "test");
        }
        try server.startServer();
    }

    // pub fn addConf(self: *Tase, conf: configs.LogConf) !void {
    //     try self.configs.append(conf);
    // }
};
