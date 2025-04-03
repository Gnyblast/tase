const std = @import("std");
const datetime = @import("datetime").datetime;

const Allocator = std.mem.Allocator;

const configs = @import("./config.zig");
const helpers = @import("../utils/helper.zig");
const serverFactory = @import("../factory/server_factory.zig");
const clientFactory = @import("../client/client_factory.zig");
const CronService = @import("../service/cron_service.zig").CronService;
const YamlParser = @import("../utils/yaml_parser.zig").YamlParseService;

pub const version = "0.0.2";

pub const Tase = struct {
    yaml_cfg: *const configs.YamlCfgContainer,
    cli_args: *const configs.argOpts,
    comptime version: []const u8 = version,
    server: serverFactory.Server,
    allocator: Allocator,

    pub fn init(allocator: Allocator, arena: Allocator, cli_args: *const configs.argOpts) !Tase {
        var server_host = cli_args.host;
        var server_port = cli_args.port;
        var server_type = cli_args.@"server-type";
        const secret = cli_args.secret orelse if (cli_args.agent) return error.SecretIsMandatory else "";

        const yaml_cfg: *configs.YamlCfgContainer = try allocator.create(configs.YamlCfgContainer);

        if (cli_args.master) {
            yaml_cfg.* = try YamlParser.parse(arena, cli_args.config);
            server_host = yaml_cfg.server.host;
            server_port = yaml_cfg.server.port;
            server_type = yaml_cfg.server.type;
        }

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
        self.allocator.destroy(self.yaml_cfg);
    }

    pub fn run(self: Tase) !void {
        try self.performCheck();
        const run_type = if (self.cli_args.agent) "Agent" else "Master";
        helpers.printApplicationInfo(run_type, self.version, self.cli_args.host, self.cli_args.port);
        if (self.cli_args.agent)
            try self.server.startAgentServer()
        else {
            if (self.yaml_cfg.agents != null) {
                const tz = try datetime.timezones.getByName(self.yaml_cfg.server.time_zone.?);
                // const cron_service = try cronService.init(self.yaml_cfg.configs, tz);

                const cron_service = try CronService.init(self.allocator, self.yaml_cfg.configs, tz);
                const thread = try std.Thread.spawn(.{}, CronService.start, .{cron_service});
                thread.detach();
                self.server.setAgents(self.yaml_cfg.agents.?);
                try self.server.startMasterServer();

                // const client = try clientFactory.getClient(self.allocator, "tcp", "127.0.0.1", 7423, "b9d36fa4b6cd3d8a2f5527c792143bfc");
                // defer client.destroy(self.allocator);
                // try client.sendMessage(&self.yaml_cfg.*.configs[0], self.allocator);
            }
        }
    }

    fn performCheck(self: Tase) !void {
        std.log.debug("Doing initial value checks", .{});
        if (self.cli_args.master) {
            try self.yaml_cfg.isValidYaml(self.allocator);
        }

        if (!self.cli_args.master and !self.cli_args.agent) {
            return error.MasterOrAgent;
        }
        if (self.cli_args.master and self.cli_args.agent) {
            return error.OnlyMasterOrAgent;
        }
        if (self.cli_args.agent) {
            if (self.cli_args.secret == null) {
                return error.SecretIsMandatory;
            }
            if (self.cli_args.@"master-host" == null or self.cli_args.@"master-host".?.len < 1) {
                return error.MasterHostRequired;
            }
            if (self.cli_args.@"master-port" == null or self.cli_args.@"master-port".? < 1) {
                return error.MasterPortRequired;
            }
        }
    }
};
