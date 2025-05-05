const std = @import("std");
const enums = @import("../enum/config_enum.zig");
const utils = @import("../utils/helper.zig");
const Regex = @import("libregex").Regex;
const Allocator = std.mem.Allocator;

pub const LOCAL = "local";

pub const YamlCfgContainer = struct {
    configs: []LogConf,
    agents: ?[]Agents,
    server: MasterServerConf,

    pub fn isValidYaml(self: YamlCfgContainer, allocator: Allocator) !void {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var agent_names = std.ArrayList([]const u8).init(arena.allocator());
        var agent_host_names = std.ArrayList([]const u8).init(arena.allocator());
        defer arena.deinit();

        if (self.agents != null) {
            for (self.agents.?) |a| {
                const agent_name_lower = try utils.toLowerCaseAlloc(arena.allocator(), a.name);
                if (utils.arrayContains(u8, agent_names.items, agent_name_lower)) {
                    return error.DuplicateAgentName;
                }

                const hostname_lower = try utils.toLowerCaseAlloc(arena.allocator(), a.hostname);
                if (utils.arrayContains(u8, agent_host_names.items, hostname_lower)) {
                    return error.DuplicateAgentHostName;
                }

                if (std.mem.eql(u8, LOCAL, agent_name_lower)) {
                    return error.LocalAgentNameIsResered;
                }
                try agent_names.append(agent_name_lower);
                try agent_host_names.append(hostname_lower);
            }
        }

        for (self.configs) |c| {
            try c.isConfigValid(allocator);

            for (c.run_agent_names) |a| {
                const agent_name_lower = try utils.toLowerCaseAlloc(arena.allocator(), a);
                if (std.ascii.eqlIgnoreCase(agent_name_lower, LOCAL))
                    continue;

                if (!utils.arrayContains(u8, agent_names.items, agent_name_lower)) {
                    return error.UndefinedAgent;
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
    logs_dir: []const u8,
    log_files_regexp: []const u8,
    cron_expression: []const u8,
    run_agent_names: [][]const u8,
    action: LogAction,

    pub fn isConfigValid(self: LogConf, allocator: Allocator) !void {
        if (self.cron_expression.len < 1) {
            return error.CronCannotBeUndefined;
        }

        const regex = Regex.initWithoutComptimeFlags(allocator, self.log_files_regexp, "") catch |err| {
            std.log.err("regex \"{s}\" not valid", .{self.log_files_regexp});
            return err;
        };
        defer regex.deinit();

        return try self.action.checkActionValidity();
    }
};

pub const LogAction = struct {
    strategy: []const u8,
    rotate_archives_dir: ?[]const u8 = null,
    from: ?[]const u8 = null,
    size: ?u64 = null,
    lines: ?u64 = null,
    @"if": ?IfOperation = null,
    keep_archive: ?IfOperation = null,
    compress: ?bool = false,
    compression_type: ?[]const u8 = "gzip",
    compression_level: ?u8 = 4,

    /// Caller is resposible for freeing the memory
    pub fn dupe(self: LogAction, allocator: Allocator) !*LogAction {
        const action = try allocator.create(LogAction);
        var if_operation: ?IfOperation = null;
        if (self.@"if" != null) {
            if_operation = IfOperation{
                .condition = try utils.dupeOptString(allocator, self.@"if".?.condition),
                .operator = try utils.dupeOptString(allocator, self.@"if".?.operator),
                .operand = self.@"if".?.operand,
            };
        }

        var keep_archive: ?IfOperation = null;
        if (self.keep_archive != null) {
            keep_archive = IfOperation{
                .condition = try utils.dupeOptString(allocator, self.keep_archive.?.condition),
                .operator = try utils.dupeOptString(allocator, self.keep_archive.?.operator),
                .operand = self.keep_archive.?.operand,
            };
        }

        action.strategy = try allocator.dupe(u8, self.strategy);
        action.rotate_archives_dir = try utils.dupeOptString(allocator, self.rotate_archives_dir);
        action.from = try utils.dupeOptString(allocator, self.from);
        action.size = self.size;
        action.lines = self.lines;
        action.@"if" = if (self.@"if" != null) if_operation else null;
        action.keep_archive = if (self.keep_archive != null) keep_archive else null;
        action.compress = self.compress;
        action.compression_type = try utils.dupeOptString(allocator, self.compression_type);
        action.compression_level = self.compression_level;
        return action;
    }

    pub fn checkActionValidity(self: LogAction) !void {
        //TODO do same for keep_archive
        if (self.@"if" == null)
            return error.IfIsEmpty;
        if (self.@"if".?.condition == null) {
            return error.MissingIfCondition;
        }
        if (self.@"if".?.operand == null) {
            return error.MissingIfOperand;
        }
        if (self.@"if".?.operator == null) {
            return error.MissingIfOperator;
        }
        switch (std.meta.stringToEnum(enums.ActionStrategy, self.strategy) orelse return error.InvalidStrategy) {
            .delete => {
                //? nothing to check yet
                return;
            },
            .rotate => {
                return self.checkMandatoryFieldsForRotate();
            },
            .truncate => {
                return self.checkMandatoryFieldsForTruncate();
            },
        }
    }

    fn checkMandatoryFieldsForRotate(self: LogAction) !void {
        _ = std.meta.stringToEnum(enums.IfConditions, self.@"if".?.condition.?) orelse return error.InvalidRotateIfCondition;

        if (self.compress != null and self.compress.?) {
            if (self.compression_type == null)
                return error.CompressionTypeMandatory;

            if (self.compression_level == null)
                return error.CompressionLevelMandatory;

            if (self.compression_level.? < 4) {
                return error.CompressionLevelInvalid;
            }

            //TODO: test behaviour
            switch (std.meta.stringToEnum(enums.CompressType, self.compression_type.?) orelse return error.InvalidCompressioType) {
                .gzip,
                => {
                    return;
                },
            }
        }
    }

    fn checkMandatoryFieldsForTruncate(self: LogAction) !void {
        if (self.lines == null and self.size == null)
            return error.lineOrSizeError;

        if (self.from == null or self.from.?.len < 1) {
            return error.TruncateRequiresFromField;
        }

        _ = std.meta.stringToEnum(enums.ActionFrom, self.from.?) orelse return error.InvalidFromFieldValue;
    }
};

pub const IfOperation = struct {
    condition: ?[]const u8 = null,
    operator: ?[]const u8 = null,
    operand: ?i32 = null,
};

const MasterServerConf = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 7423,
    type: []const u8 = "tcp",
    time_zone: ?[]const u8 = "UTC",
};

pub const argOpts = struct {
    @"log-dir": []const u8 = "/var/log/tase",
    @"log-level": std.log.Level = std.log.Level.info,
    master: bool = false,
    agent: bool = false,
    config: []const u8 = "/etc/tase/app.yaml",
    secret: ?[]const u8 = null,
    host: []const u8 = "127.0.0.1",
    port: u16 = 7423,
    @"server-type": []const u8 = "tcp",
    help: bool = false,
    @"master-host": ?[]const u8 = null,
    @"master-port": ?u16 = null,

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
            .@"master-host" = "master host address",
            .@"master-port" = "master port for connection",
        },
    };
};
