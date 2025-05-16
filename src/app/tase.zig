const std = @import("std");
const testing = std.testing;
const timezones = @import("datetime").timezones;

const c = @cImport({
    @cInclude("stdlib.h");
});

const Allocator = std.mem.Allocator;

const configs = @import("./config.zig");
const enums = @import("../enum/config_enum.zig");
const helpers = @import("../utils/helper.zig");
const serverFactory = @import("../factory/server_factory.zig");
const clientFactory = @import("../factory/client_factory.zig");
const CronService = @import("../service/cron_service.zig").CronService;
const YamlParser = @import("../utils/yaml_parser.zig").YamlParseService;
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;

pub const version = "0.0.2";

pub const Tase = struct {
    yaml_cfg: *const configs.YamlCfgContainer,
    cli_args: *const configs.argOpts,
    comptime version: []const u8 = version,
    server: serverFactory.Server,
    allocator: Allocator,
    secret: []const u8,

    pub fn init(allocator: Allocator, cli_args: *const configs.argOpts) !Tase {
        var server_host = cli_args.host;
        var server_port = cli_args.port;
        var server_type = cli_args.@"server-type";

        var secret = cli_args.secret orelse "";
        var secret_dupe = try allocator.dupe(u8, secret);
        if (std.mem.eql(u8, secret, "") and cli_args.agent) {
            const env_secret = std.process.getEnvVarOwned(allocator, "TASE_AGENT_SECRET") catch {
                return TaseNativeErrors.SecretIsMandatory;
            };
            defer allocator.free(env_secret);
            secret = env_secret;
            allocator.free(secret_dupe);
            secret_dupe = try allocator.dupe(u8, secret);
        }

        const yaml_cfg: *configs.YamlCfgContainer = try allocator.create(configs.YamlCfgContainer);
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        if (cli_args.master) {
            yaml_cfg.* = try YamlParser.parse(arena.allocator(), cli_args.config);
            server_host = yaml_cfg.server.host;
            server_port = yaml_cfg.server.port;
            server_type = yaml_cfg.server.type;
            for (0..yaml_cfg.*.configs.len) |i| {
                if (std.mem.eql(u8, yaml_cfg.*.configs[i].action.strategy, enums.ActionStrategy.rotate.str()) and yaml_cfg.*.configs[i].action.rotate_archives_dir == null) {
                    yaml_cfg.*.configs[i].action.rotate_archives_dir = yaml_cfg.*.configs[i].logs_dir;
                }
            }
        }

        const server = try serverFactory.getServer(allocator, server_type, server_host, server_port, secret_dupe);

        return Tase{
            .allocator = allocator,
            .cli_args = cli_args,
            .yaml_cfg = yaml_cfg,
            .server = server,
            .secret = secret_dupe,
        };
    }

    pub fn deinit(self: *Tase) void {
        self.server.destroy(self.allocator);
        self.allocator.destroy(self.yaml_cfg);
        self.allocator.free(self.secret);
    }

    pub fn run(self: Tase) !void {
        try self.performCheck();
        const run_type = if (self.cli_args.agent) "Agent" else "Master";
        helpers.printApplicationInfo(run_type, self.version, self.cli_args.host, self.cli_args.port);
        if (self.cli_args.agent)
            try self.server.startAgentServer()
        else {
            if (self.yaml_cfg.agents != null) {
                const tz = try timezones.getByName(self.yaml_cfg.server.time_zone.?);
                // const cron_service = try cronService.init(self.yaml_cfg.configs, tz);

                const cron_service = try CronService.init(self.yaml_cfg.configs, self.yaml_cfg.agents, self.yaml_cfg.server.type, tz);
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
            return TaseNativeErrors.MasterOrAgent;
        }
        if (self.cli_args.master and self.cli_args.agent) {
            return TaseNativeErrors.OnlyMasterOrAgent;
        }
        if (self.cli_args.agent) {
            if (std.mem.eql(u8, self.secret, "")) {
                return TaseNativeErrors.SecretIsMandatory;
            }
            if (self.cli_args.@"master-host" == null or self.cli_args.@"master-host".?.len < 1) {
                return TaseNativeErrors.MasterHostRequired;
            }
            if (self.cli_args.@"master-port" == null or self.cli_args.@"master-port".? < 1) {
                return TaseNativeErrors.MasterPortRequired;
            }
        }
    }
};

test "initDeinitTest" {
    const TestCase = struct {
        cli: configs.argOpts,
        set_env: ?bool = false,
        err: ?anyerror = null,
    };

    const tcs = [_]TestCase{
        .{
            .cli = configs.argOpts{
                .master = true,
                .config = "./app.yaml",
            },
        },
        .{
            .cli = configs.argOpts{
                .agent = true,
            },
            .err = TaseNativeErrors.SecretIsMandatory,
        },
        .{
            .cli = configs.argOpts{
                .agent = true,
            },
            .set_env = true,
        },
        .{
            .cli = configs.argOpts{
                .agent = true,
                .secret = "767asd6as78d678asd68as",
            },
        },
    };
    for (tcs) |tc| {
        if (tc.err != null) {
            try testing.expectError(tc.err.?, Tase.init(testing.allocator, &tc.cli));
        } else {
            if (tc.set_env.?)
                _ = c.setenv("TASE_AGENT_SECRET", "as7j8d6as78d6n7asd", 1);

            var tase = try Tase.init(testing.allocator, &tc.cli);
            defer tase.deinit();
        }
    }
}

test "performCheckTest" {
    // var tase = try Tase.init(testing.allocator, &cli);
    // defer tase.deinit();
    var agents = [_]configs.Agent{
        configs.Agent{
            .hostname = "remotehost",
            .name = "test",
            .port = 7424,
            .secret = "78asd6n7a8sd6hsa8a978ns6md78as6d",
        },
    };
    var as = [_][]const u8{ "test", "local" };
    var cfs = [_]configs.LogConf{
        configs.LogConf{
            .app_name = "test",
            .cron_expression = "5 4 * * *",
            .log_files_regexp = "test.log",
            .logs_dir = "/var/log/tase",
            .run_agent_names = &as,
            .action = configs.LogAction{
                .strategy = "delete",
                .@"if" = configs.IfOperation{
                    .condition = "days",
                    .operator = ">",
                    .operand = 2,
                },
            },
        },
    };
    var server = try serverFactory.getServer(testing.allocator, "tcp", "localhost", 7423, "");
    defer server.destroy(testing.allocator);

    const TestCase = struct {
        tase: Tase,
        err: ?anyerror = null,
    };

    const tcs = [_]TestCase{
        .{
            .tase = Tase{
                .allocator = testing.allocator,
                .cli_args = &configs.argOpts{
                    .config = "../../app.yaml",
                },
                .secret = "",
                .version = version,
                .server = server,
                .yaml_cfg = &configs.YamlCfgContainer{
                    .agents = &agents,
                    .server = configs.MasterServerConf{
                        .host = "localhost",
                        .port = 7424,
                        .time_zone = "Asia/Nicosia",
                        .type = "tcp",
                    },
                    .configs = &cfs,
                },
            },
            .err = TaseNativeErrors.MasterOrAgent,
        },
        .{
            .tase = Tase{
                .allocator = testing.allocator,
                .cli_args = &configs.argOpts{
                    .config = "../../app.yaml",
                    .master = true,
                },
                .secret = "",
                .version = version,
                .server = server,
                .yaml_cfg = &configs.YamlCfgContainer{
                    .agents = &agents,
                    .server = configs.MasterServerConf{
                        .host = "localhost",
                        .port = 7424,
                        .time_zone = "Asia/Nicosia",
                        .type = "tcp",
                    },
                    .configs = &cfs,
                },
            },
        },
        .{
            .tase = Tase{
                .allocator = testing.allocator,
                .cli_args = &configs.argOpts{
                    .config = "../../app.yaml",
                    .master = true,
                    .agent = true,
                },
                .secret = "",
                .version = version,
                .server = server,
                .yaml_cfg = &configs.YamlCfgContainer{
                    .agents = &agents,
                    .server = configs.MasterServerConf{
                        .host = "localhost",
                        .port = 7424,
                        .time_zone = "Asia/Nicosia",
                        .type = "tcp",
                    },
                    .configs = &cfs,
                },
            },
            .err = TaseNativeErrors.OnlyMasterOrAgent,
        },
        .{
            .tase = Tase{
                .allocator = testing.allocator,
                .cli_args = &configs.argOpts{
                    .config = "../../app.yaml",
                    .agent = true,
                },
                .secret = "",
                .version = version,
                .server = server,
                .yaml_cfg = &configs.YamlCfgContainer{
                    .agents = &agents,
                    .server = configs.MasterServerConf{
                        .host = "localhost",
                        .port = 7424,
                        .time_zone = "Asia/Nicosia",
                        .type = "tcp",
                    },
                    .configs = &cfs,
                },
            },
            .err = TaseNativeErrors.SecretIsMandatory,
        },
        .{
            .tase = Tase{
                .allocator = testing.allocator,
                .cli_args = &configs.argOpts{
                    .config = "../../app.yaml",
                    .agent = true,
                },
                .secret = "78asas6n7j8as67m9das6n7m9asd79",
                .version = version,
                .server = server,
                .yaml_cfg = &configs.YamlCfgContainer{
                    .agents = &agents,
                    .server = configs.MasterServerConf{
                        .host = "localhost",
                        .port = 7424,
                        .time_zone = "Asia/Nicosia",
                        .type = "tcp",
                    },
                    .configs = &cfs,
                },
            },
            .err = TaseNativeErrors.MasterHostRequired,
        },
        .{
            .tase = Tase{
                .allocator = testing.allocator,
                .cli_args = &configs.argOpts{
                    .config = "../../app.yaml",
                    .agent = true,
                    .@"master-host" = "localhost",
                },
                .secret = "78asas6n7j8as67m9das6n7m9asd79",
                .version = version,
                .server = server,
                .yaml_cfg = &configs.YamlCfgContainer{
                    .agents = &agents,
                    .server = configs.MasterServerConf{
                        .host = "localhost",
                        .port = 7424,
                        .time_zone = "Asia/Nicosia",
                        .type = "tcp",
                    },
                    .configs = &cfs,
                },
            },
            .err = TaseNativeErrors.MasterPortRequired,
        },
        .{
            .tase = Tase{
                .allocator = testing.allocator,
                .cli_args = &configs.argOpts{
                    .config = "../../app.yaml",
                    .agent = true,
                    .@"master-host" = "localhost",
                    .@"master-port" = 7423,
                },
                .secret = "78asas6n7j8as67m9das6n7m9asd79",
                .version = version,
                .server = server,
                .yaml_cfg = &configs.YamlCfgContainer{
                    .agents = &agents,
                    .server = configs.MasterServerConf{
                        .host = "localhost",
                        .port = 7424,
                        .time_zone = "Asia/Nicosia",
                        .type = "tcp",
                    },
                    .configs = &cfs,
                },
            },
        },
    };

    for (tcs) |tc| {
        if (tc.err != null)
            try testing.expectError(tc.err.?, tc.tase.performCheck())
        else
            try tc.tase.performCheck();
    }
}
