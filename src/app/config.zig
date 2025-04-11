const std = @import("std");
const enums = @import("../enum/config_enum.zig");
const utils = @import("../utils/helper.zig");
const Regex = @import("libregex").Regex;
const Allocator = std.mem.Allocator;

const LOCAL = "local";

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
                if (utils.arrayContains(u8, agent_names.items, a.name)) {
                    return error.DuplicateAgentName;
                }
                if (utils.arrayContains(u8, agent_host_names.items, a.hostname)) {
                    return error.DuplicateAgentHostName;
                }
                try agent_names.append(a.name);
                try agent_host_names.append(a.hostname);
            }
        }

        for (self.configs) |c| {
            try c.isConfigValid(allocator);

            for (c.run_agent_name) |a| {
                if (std.mem.eql(u8, a, LOCAL))
                    continue;

                if (!utils.arrayContains(u8, agent_names.items, a)) {
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
    run_agent_name: [][]const u8,
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
    from: ?[]const u8 = null,
    by: ?[]const u8 = null,
    size: ?u32 = null,
    delete_older_than_days: ?u32 = 7,
    compress: ?bool = false,
    compression_type: ?[]const u8 = "gzip",
    compression_level: ?u8 = 0,

    fn checkActionValidity(self: LogAction) !void {
        switch (std.meta.stringToEnum(enums.ActionStrategy, self.strategy) orelse return error.InvalidStrategy) {
            enums.ActionStrategy.delete => {
                return self.checkMandatoryFieldsForDelete();
            },
            enums.ActionStrategy.rotate => {
                return self.checkMandatoryFieldsForRotate();
            },
            enums.ActionStrategy.truncate => {
                return self.checkMandatoryFieldsForTruncate();
            },
        }
    }

    fn checkMandatoryFieldsForDelete(self: LogAction) !void {
        if (self.delete_older_than_days == null or self.delete_older_than_days.? < 1)
            return error.NDaysOldRequired;

        return;
    }

    fn checkMandatoryFieldsForRotate(self: LogAction) !void {
        if (self.by == null or self.by.?.len < 1) {
            return error.RotateRequiresByField;
        }

        switch (std.meta.stringToEnum(enums.ActionBy, self.by.?) orelse return error.InvalidRotateBy) {
            enums.ActionBy.days, enums.ActionBy.megabytes => {},
            else => return error.InvalidRotateBy,
        }

        if (self.size == null or self.size.? < 1) {
            return error.SizeIsRequiredForRotate;
        }

        if (self.compress != null and self.compress.?) {
            if (self.compression_type == null)
                return error.CompressionTypeMandatory;

            if (self.compression_level == null or self.compression_level.? < 0)
                return error.CompressionLevelMandatory;

            switch (std.meta.stringToEnum(enums.CompressType, self.compression_type.?) orelse return error.InvalidCompressioType) {
                enums.CompressType.gzip, enums.CompressType.xz, enums.CompressType.zstd => {
                    return;
                },
            }
        }
    }

    fn checkMandatoryFieldsForTruncate(self: LogAction) !void {
        if (self.by == null or self.by.?.len < 1) {
            return error.TruncateRequiresByField;
        }

        switch (std.meta.stringToEnum(enums.ActionBy, self.by.?) orelse return error.InvalidTruncateBy) {
            enums.ActionBy.lines, enums.ActionBy.megabytes => {},
            else => return error.InvalidTruncateBy,
        }

        if (self.size == null or self.size.? < 1) {
            return error.SizeIsRequiredForTruncate;
        }

        if (self.from == null or self.from.?.len < 1) {
            return error.TruncateRequiresFromField;
        }

        _ = std.meta.stringToEnum(enums.ActionFrom, self.from.?) orelse return error.InvalidFromFieldValue;
    }
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
