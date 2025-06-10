const std = @import("std");
const testing = std.testing;
const datetime = @import("datetime").datetime;
const cron = @import("cron-time").Cron;
const Allocator = std.mem.Allocator;
const Pruner = @import("../service/pruner.zig").Pruner;
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;

const configs = @import("../app/config.zig");
const clientFactory = @import("../factory/client_factory.zig");
const errorFactory = @import("../factory/error_factory.zig");
const utils = @import("../utils/helper.zig");

pub const CronService = struct {
    confs: []configs.LogConf,
    tz: datetime.Timezone,
    agents: ?[]configs.Agent,
    server_type: []const u8,

    pub fn init(cfgs: []configs.LogConf, agents: ?[]configs.Agent, server_type: []const u8, timezone: datetime.Timezone) !CronService {
        try validateCronExpression(cfgs);
        return .{
            .confs = cfgs,
            .tz = timezone,
            .agents = agents,
            .server_type = server_type,
        };
    }

    //test-no-cover-start
    pub fn start(self: CronService) void {
        var da: std.heap.DebugAllocator(.{}) = .init;
        defer {
            const leaks = da.deinit();
            std.debug.assert(leaks == .ok);
        }

        const allocator = da.allocator();

        std.time.sleep(getSleepInNS(datetime.Datetime.now()));

        while (true) {
            for (self.confs) |cfg| {
                if (self.isItTime(cfg.app_name, cfg.cron_expression) catch {
                    std.log.scoped(.cron).err("Error calculating next run for {s} with cron: {s} ", .{ cfg.app_name, cfg.cron_expression });
                    continue;
                }) {
                    std.log.scoped(.cron).info("Running logs processing for {s} with cron: {s}", .{ cfg.app_name, cfg.cron_expression });

                    const agents = self.getAgentsByName(allocator, cfg.run_agent_names) catch |err| {
                        const err_msg = errorFactory.getLogMessageByErr(allocator, err);
                        defer if (err_msg.allocated) allocator.free(err_msg.message);
                        std.log.scoped(.cron).err("problem getting agents: {s}", .{err_msg.message});
                        continue;
                    };
                    defer agents.deinit();

                    std.log.scoped(.cron).info("Running for {d} agent(s)", .{agents.items.len});
                    for (agents.items) |agent| {
                        self.processForAgent(allocator, cfg, agent);
                    }
                }
            }

            std.time.sleep(std.time.ns_per_min);
        }
    }
    //test-no-cover-end

    fn isItTime(self: CronService, app_name: []const u8, cron_expression: []const u8) !bool {
        std.log.scoped(.cron).debug("processing cron {s}: {s}", .{ app_name, cron_expression });
        const date = datetime.Datetime.now().shiftTimezone(self.tz);
        var c = cron.init();
        try c.parse(cron_expression);
        const next = try c.next(date);
        const duration = next.sub(date);
        return duration.seconds < 59;
    }

    fn getAgentsByName(self: CronService, allocator: Allocator, agent_names: [][]const u8) !std.ArrayList(configs.Agent) {
        var agents = std.ArrayList(configs.Agent).init(allocator);
        for (agent_names) |name| {
            if (std.ascii.eqlIgnoreCase(name, configs.LOCAL)) {
                try agents.append(configs.Agent{
                    .hostname = "localhost",
                    .name = configs.LOCAL,
                    .port = 0,
                    .secret = "",
                });
                continue;
            }

            for (self.agents.?) |agent| {
                if (std.ascii.eqlIgnoreCase(agent.name, name)) {
                    try agents.append(agent);
                }
            }
        }

        if (agents.items.len > 0) {
            return agents;
        }

        return TaseNativeErrors.NoAgentsFound;
    }

    //test-no-cover-start
    fn processForAgent(self: CronService, allocator: Allocator, cfg: configs.LogConf, agent: configs.Agent) void {
        if (std.ascii.eqlIgnoreCase(agent.name, configs.LOCAL)) {
            self.localRun(allocator, cfg);
            return;
        }

        self.remoteRun(allocator, cfg, agent);
    }
    //test-no-cover-end

    //test-no-cover-start
    fn localRun(self: CronService, allocator: Allocator, cfg: configs.LogConf) void {
        const pruner = Pruner.create(
            allocator,
            self.tz,
            cfg.logs_dir,
            cfg.log_files_regexp,
            cfg.action,
        ) catch |err| {
            std.log.scoped(.server).err("error init logs service: {}", .{err});
            return;
        };

        const thread = std.Thread.spawn(.{}, Pruner.runAndDestroy, .{pruner}) catch |err| {
            std.log.scoped(.cron).err("Error while running local task on a thread: {}", .{err});
            return;
        };
        thread.detach();
        return;
    }
    //test-no-cover-end

    //test-no-cover-start
    fn remoteRun(self: CronService, allocator: Allocator, cfg: configs.LogConf, agent: configs.Agent) void {
        const tcp_client = clientFactory.getClient(allocator, self.server_type, agent.hostname, agent.port, agent.secret) catch |err| {
            const err_msg = errorFactory.getLogMessageByErr(allocator, err);
            defer if (err_msg.allocated) allocator.free(err_msg.message);
            std.log.scoped(.cron).err("problem getting client to agent: {s}", .{err_msg.message});
            return;
        };
        defer tcp_client.destroy(allocator);
        tcp_client.sendLogConf(allocator, cfg, self.tz) catch |err| {
            const err_msg = errorFactory.getLogMessageByErr(allocator, err);
            defer if (err_msg.allocated) allocator.free(err_msg.message);
            std.log.scoped(.cron).err("problem sending message to agent: {s}", .{err_msg.message});
            return;
        };
    }
    //test-no-cover-end

    fn validateCronExpression(confs: []configs.LogConf) !void {
        for (confs) |cfg| {
            var c = cron.init();
            try c.parse(cfg.cron_expression);
        }
    }

    fn getSleepInNS(until: datetime.Datetime) u64 {
        const m: u64 = std.time.ns_per_s;
        const sleep_seconds = (59 - until.time.second);
        const sleep_nano_seconds = sleep_seconds * m;
        return sleep_nano_seconds;
    }
};

var test_agent_names = [_][]const u8{ "test", "Foo", "Bar" };
var test_confs = [_]configs.LogConf{
    configs.LogConf{
        .app_name = "test",
        .cron_expression = "* * * * *",
        .log_files_regexp = "test.log",
        .logs_dir = "/var/log/tase",
        .run_agent_names = &test_agent_names,
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
var test_agents = [_]configs.Agent{
    .{
        .hostname = "remotehost",
        .name = "test",
        .port = 7424,
        .secret = "78asd6n7a8sd6hsa8a978ns6md78as6d",
    },
    .{
        .hostname = "localhost",
        .name = "local",
        .port = 7424,
        .secret = "78asd6n7a8sd6hsa8a978ns6md78as6d",
    },
};

test "initTest" {
    _ = try CronService.init(&test_confs, &test_agents, "tcp", datetime.timezones.Asia.Nicosia);
}

test "isItTimeTest" {
    const cs = try CronService.init(&test_confs, &test_agents, "tcp", datetime.timezones.Asia.Nicosia);
    try testing.expectEqual(true, try cs.isItTime(cs.confs[0].app_name, cs.confs[0].cron_expression));
}

test "getAgentsByNameTest" {
    var a3_err = [_][]const u8{ "Hello", "Foo", "Bar" };

    const cs = try CronService.init(&test_confs, &test_agents, "tcp", datetime.timezones.Asia.Nicosia);
    const as = try cs.getAgentsByName(testing.allocator, &test_agent_names);
    defer as.deinit();
    try testing.expectError(TaseNativeErrors.NoAgentsFound, cs.getAgentsByName(testing.allocator, &a3_err));
}

test "sleepTest" {
    const actual = CronService.getSleepInNS(try datetime.Datetime.create(2025, 5, 13, 10, 10, 50, 0, datetime.timezones.Asia.Nicosia));
    try testing.expect(9000000000 <= actual and 10000000000 >= actual);
}
