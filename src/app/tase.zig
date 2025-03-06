const std = @import("std");

const Allocator = std.mem.Allocator;

const configs = @import("./config.zig");
const helpers = @import("../utils/helper.zig");
const serverFactory = @import("../server/server_factory.zig");
const clientFactory = @import("../client/client_factory.zig");

pub const version = "0.0.1";

pub const Tase = struct {
    yaml_cfg: *const configs.YamlCfgContainer,
    cli_args: *const configs.argOpts,
    comptime version: []const u8 = version,
    server: serverFactory.Server,
    allocator: Allocator,

    pub fn init(allocator: Allocator, cli_args: *const configs.argOpts, yaml_cfg: *const configs.YamlCfgContainer) !Tase {
        const server_type = if (cli_args.agent) cli_args.@"server-type" else yaml_cfg.server.type;
        const server_host = if (cli_args.agent) cli_args.host else yaml_cfg.server.host;
        const server_port = if (cli_args.agent) cli_args.port else yaml_cfg.server.port;
        const secret = cli_args.secret orelse if (cli_args.agent) return error.SecretIsMandatoryForAgents else "";

        const server = try serverFactory.getServer(allocator, server_type, server_host, server_port, secret);

        return Tase{
            .allocator = allocator,
            .cli_args = cli_args,
            .yaml_cfg = yaml_cfg,
            .server = server,
        };
    }

    pub fn deinit(self: *Tase) void {
        self.server.destroy(self.allocator);
    }

    pub fn run(self: Tase) !void {
        // try self.performCheck();
        helpers.printApplicationInfo(self.version);
        if (self.cli_args.agent)
            try self.server.startAgentServer()
        else {
            self.server.setAgents(self.yaml_cfg.agents);
            // try self.server.startMasterServer();
            const client = try clientFactory.getClient(self.allocator, "tcp", "127.0.0.1", 7423, "b9d36fa4b6cd3d8a2f5527c792143bfc");
            defer client.destroy(self.allocator);
            try client.sendMessage(&self.yaml_cfg.*.configs[0], self.allocator);
        }
    }

    fn performCheck(self: Tase) !void {
        std.log.debug("Doing initial value checks", .{});
        try self.yaml_cfg.isValidYaml(self.allocator);

        if (!self.cli_args.master and !self.cli_args.agent) {
            return error.ServerMustStartedEitherAsMasterOrAgent;
        }
        if (self.cli_args.master and self.cli_args.agent) {
            return error.ServerCannotBeStartedBothAsMasterAndAgent;
        }
        if (self.cli_args.agent and self.cli_args.secret == null) {
            return error.SecretIsMandatoryForAgents;
        }
    }
};
