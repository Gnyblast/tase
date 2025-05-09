const std = @import("std");
const datetime = @import("datetime").datetime;
const cron = @import("cron-time").Cron;
const Allocator = std.mem.Allocator;
const LogsService = @import("../service/logs_service.zig").LogService;
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;

const configs = @import("../app/config.zig");
const clientFactory = @import("../factory/client_factory.zig");
const errorFactory = @import("../factory/error_factory.zig");
const utils = @import("../utils/helper.zig");

pub const CronService = struct {
    confs: []configs.LogConf,
    tz: datetime.Timezone,
    agents: ?[]configs.Agents,
    server_type: []const u8,

    pub fn init(cfgs: []configs.LogConf, agents: ?[]configs.Agents, server_type: []const u8, timezone: datetime.Timezone) !CronService {
        try validateCronExpression(cfgs);
        return .{
            .confs = cfgs,
            .tz = timezone,
            .agents = agents,
            .server_type = server_type,
        };
    }

    pub fn start(self: CronService) void {
        var da: std.heap.DebugAllocator(.{}) = .init;
        defer {
            const leaks = da.deinit();
            std.debug.assert(leaks == .ok);
        }

        const allocator = da.allocator();

        sleepUntilNewMinute();
        while (true) {
            for (self.confs) |cfg| {
                std.log.scoped(.cron).debug("processing cron {s}: {s}", .{ cfg.app_name, cfg.cron_expression });
                const date = datetime.Datetime.now().shiftTimezone(self.tz);
                var c = cron.init();
                c.parse(cfg.cron_expression) catch |err| {
                    std.log.scoped(.cron).err("error parsing cron {s}: {}", .{ cfg.cron_expression, err });
                    continue;
                };
                const next = c.next(date) catch |err| {
                    std.log.scoped(.cron).err("error calculating next run {}", .{err});
                    continue;
                };
                const duration = next.sub(date);

                if (duration.seconds < 59) {
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
                        if (std.ascii.eqlIgnoreCase(agent.name, configs.LOCAL)) {
                            var tz = self.tz;
                            var action = cfg.action;
                            const logsService = LogsService.init(
                                null,
                                &tz,
                                cfg.logs_dir,
                                cfg.log_files_regexp,
                                &action,
                            );

                            const thread = std.Thread.spawn(.{}, LogsService.run, .{logsService}) catch |err| {
                                std.log.scoped(.cron).err("Error while running local task on a thread: {}", .{err});
                                continue;
                            };
                            thread.detach();
                            continue;
                        }

                        const tcp_client = clientFactory.getClient(allocator, self.server_type, agent.hostname, agent.port, agent.secret) catch |err| {
                            const err_msg = errorFactory.getLogMessageByErr(allocator, err);
                            defer if (err_msg.allocated) allocator.free(err_msg.message);
                            std.log.scoped(.cron).err("problem gettin client to agent: {s}", .{err_msg.message});
                            continue;
                        };
                        defer tcp_client.destroy(allocator);
                        tcp_client.sendLogConf(allocator, cfg, self.tz) catch |err| {
                            const err_msg = errorFactory.getLogMessageByErr(allocator, err);
                            defer if (err_msg.allocated) allocator.free(err_msg.message);
                            std.log.scoped(.cron).err("problem sending message to agent: {s}", .{err_msg.message});
                            continue;
                        };
                    }
                } else {
                    //TODO remove this
                    std.debug.print("running in {d} seconds\n", .{duration.seconds});
                }
            }

            std.time.sleep(std.time.ns_per_min);
        }
    }

    fn getAgentsByName(self: CronService, allocator: Allocator, agent_names: [][]const u8) !std.ArrayList(configs.Agents) {
        var agents = std.ArrayList(configs.Agents).init(allocator);
        for (agent_names) |name| {
            if (std.ascii.eqlIgnoreCase(name, configs.LOCAL)) {
                try agents.append(configs.Agents{
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

    fn validateCronExpression(confs: []configs.LogConf) !void {
        for (confs) |cfg| {
            var c = cron.init();
            try c.parse(cfg.cron_expression);
        }
    }

    fn sleepUntilNewMinute() void {
        const now = datetime.Datetime.now();
        const m: u64 = std.time.ns_per_s;
        const sleep_seconds = (59 - now.time.second);
        const sleep_nano_seconds = sleep_seconds * m;

        //TODO remove this
        std.debug.print("Sleeping for {d} seconds\n", .{sleep_seconds});
        std.time.sleep(sleep_nano_seconds);
    }
};
