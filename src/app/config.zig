const std = @import("std");
const enums = @import("../enum/config_enum.zig");
const utils = @import("../utils/helper.zig");
const Allocator = std.mem.Allocator;

pub const YamlCfgContainer = struct {
    configs: []LogConf,
    agents: []Agents,
    server: MasterServerConf,

    pub fn isValidYaml(self: YamlCfgContainer, allocator: Allocator) !void {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var agent_names = std.ArrayList([]const u8).init(arena.allocator());
        var agent_host_names = std.ArrayList([]const u8).init(arena.allocator());
        defer arena.deinit();
        for (self.agents) |a| {
            if (utils.arrayContains(u8, agent_names.items, a.name)) {
                return error.DuplicateAgentName;
            }
            if (utils.arrayContains(u8, agent_host_names.items, a.hostname)) {
                return error.DuplicateAgentHostName;
            }
            try agent_names.append(a.name);
            try agent_host_names.append(a.hostname);
        }

        for (self.configs) |c| {
            try c.isConfigValid();

            for (c.run_agent_name) |a| {
                if (!utils.arrayContains(u8, agent_names.items, a)) {
                    return error.ConfigAgentNotDefinedInAgents;
                }
            }
        }

        return;
    }
};

pub const Agents = struct {
    name: []const u8,
    hostname: []const u8,
    port: u16,
    secret: []const u8,
};

pub const LogConf = struct {
    app_name: []const u8,
    log_path: []const u8,
    cron_expression: []const u8,
    run_agent_name: [][]const u8,
    action: LogAction,

    pub fn isConfigValid(self: LogConf) !void {
        if (self.cron_expression.len < 1) {
            return error.CronCannotBeUndefined;
        }

        return try self.action.checkConfigValidity();
    }
};

const LogAction = struct {
    strategy: []const u8,
    from: []const u8,
    by: []const u8,
    size: u32 = 1024,
    days_old: u32 = 7,

    fn checkConfigValidity(self: LogAction) !void {
        if (std.mem.eql(u8, self.strategy, enums.ActionStrategy.str(enums.ActionStrategy.rotate)) or
            (std.mem.eql(u8, self.strategy, enums.ActionStrategy.str(enums.ActionStrategy.delete))))
        {
            if (self.days_old < 1) {
                return error.DeleteRequiresDaysOldField;
            }
        } else if (std.mem.eql(u8, self.strategy, enums.ActionStrategy.str(enums.ActionStrategy.truncate))) {
            if (self.by.len < 1) {
                return error.TruncateRequiresByField;
            }
            if (!self.isActionByValid()) {
                return error.InvalidByFieldValue;
            }

            if (self.from.len < 1) {
                return error.TruncateRequiresFromField;
            }
            if (!self.isActionFromValid()) {
                return error.InvalidFromFieldValue;
            }
        } else {
            return error.UnknownStrategy;
        }
    }

    fn isActionByValid(self: LogAction) bool {
        if (std.mem.eql(u8, self.by, enums.ActionBy.str(enums.ActionBy.megaBytes)) or
            std.mem.eql(u8, self.by, enums.ActionBy.str(enums.ActionBy.lines)))
        {
            return true;
        } else {
            return false;
        }
    }

    fn isActionFromValid(self: LogAction) bool {
        if (std.mem.eql(u8, self.from, enums.ActionFrom.str(enums.ActionFrom.fromBottom)) or
            std.mem.eql(u8, self.from, enums.ActionFrom.str(enums.ActionFrom.fromTop)))
        {
            return true;
        } else {
            return false;
        }
    }
};

const MasterServerConf = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 7423,
    type: []const u8 = "tcp",
};

pub const argOpts = struct {
    @"log-dir": []const u8 = "/var/log/tase",
    @"log-level": std.log.Level = std.log.default_level,
    master: bool = false,
    agent: bool = false,
    config: []const u8 = "/etc/tase/app.yaml",
    secret: ?[]const u8 = null,
    host: []const u8 = "127.0.0.1",
    port: u16 = 7423,
    @"server-type": []const u8 = "tcp",
    help: bool = false,

    pub const meta = .{
        .option_docs = .{
            .@"log-dir" = "Directory path for log files of the tase app",
            .@"log-level" = "Log levels: DEBUG, INFO, ERROR, FATAL",
            .master = "Set this if this server will be the master",
            .agent = "Set this if this server will be one of the agents",
            .config = "YAML config file path",
            .secret = "Secret for the JWT communication",
            .host = "Server host address for agent/master communication: default: 127.0.0.1",
            .port = "Server port for agent/master communication: default: 7423",
            .@"server-type" = "Server type for agent/master communication",
            .help = "Print help",
        },
    };
};
