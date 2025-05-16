const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const Cron = @import("cron-time").Cron;
const enums = @import("../enum/config_enum.zig");
const utils = @import("../utils/helper.zig");
const Regex = @import("libregex").Regex;
const Allocator = std.mem.Allocator;
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;

pub const LOCAL = "local";

pub const YamlCfgContainer = struct {
    configs: []LogConf,
    agents: ?[]Agent,
    server: MasterServerConf,

    pub fn isValidYaml(self: YamlCfgContainer, allocator: Allocator) !void {
        std.log.scoped(.config).debug("Validation check for YAML config", .{});
        var arena = std.heap.ArenaAllocator.init(allocator);
        var agent_names = std.ArrayList([]const u8).init(arena.allocator());
        var agent_host_names = std.ArrayList([]const u8).init(arena.allocator());
        defer arena.deinit();

        if (self.agents != null) {
            for (self.agents.?) |a| {
                const agent_name_lower = try utils.toLowerCase(arena.allocator(), a.name);
                if (utils.arrayContains(u8, agent_names.items, agent_name_lower)) {
                    return TaseNativeErrors.DuplicateAgentName;
                }

                const hostname_lower = try utils.toLowerCase(arena.allocator(), a.hostname);
                if (utils.arrayContains(u8, agent_host_names.items, hostname_lower)) {
                    return TaseNativeErrors.DuplicateAgentHostName;
                }

                if (std.mem.eql(u8, LOCAL, agent_name_lower)) {
                    return TaseNativeErrors.LocalAgentNameIsReserved;
                }
                try agent_names.append(agent_name_lower);
                try agent_host_names.append(hostname_lower);
            }
        }

        for (self.configs) |c| {
            std.log.scoped(.config).debug("Validation check for app config {s}", .{c.app_name});
            try c.isConfigValid(allocator);

            for (c.run_agent_names) |a| {
                const agent_name_lower = try utils.toLowerCase(arena.allocator(), a);
                if (std.ascii.eqlIgnoreCase(agent_name_lower, LOCAL))
                    continue;

                if (!utils.arrayContains(u8, agent_names.items, agent_name_lower)) {
                    return TaseNativeErrors.UndefinedAgent;
                }
            }
        }

        return;
    }
};

pub const Agent = struct {
    name: []const u8,
    hostname: []const u8,
    port: u16,
    secret: []const u8,
};

//TODO revisit this on future version for builtin.is_test
pub const LogConf = struct {
    app_name: []const u8,
    logs_dir: []const u8,
    log_files_regexp: []const u8,
    cron_expression: []const u8,
    run_agent_names: [][]const u8,
    action: LogAction,

    pub fn isConfigValid(self: LogConf, allocator: Allocator) !void {
        var cron = Cron.init();
        cron.parse(self.cron_expression) catch |err| {
            if (!builtin.is_test) std.log.scoped(.config).err("Error parsing cron: {s}", .{self.cron_expression});
            return err;
        };

        const regex = try Regex.initWithoutComptimeFlags(allocator, self.log_files_regexp, "");
        defer regex.deinit();

        return try self.action.checkActionValidity();
    }
};

pub const LogAction = struct {
    strategy: []const u8,
    rotate_archives_dir: ?[]const u8 = null,
    truncate_settings: ?TruncateSettings = null,
    @"if": ?IfOperation = null,
    keep_archive: ?IfOperation = null,
    compress: ?[]const u8 = null,
    compression_level: ?u8 = 4,

    /// Caller is resposible for freeing the memory
    pub fn dupe(self: LogAction, allocator: Allocator) !*LogAction {
        const action = try allocator.create(LogAction);
        var if_operation: ?IfOperation = null;
        if (self.@"if" != null) {
            if_operation = IfOperation{
                .condition = try allocator.dupe(u8, self.@"if".?.condition.?),
                .operator = try allocator.dupe(u8, self.@"if".?.operator.?),
                .operand = self.@"if".?.operand.?,
            };
        }

        var keep_archive: ?IfOperation = null;
        if (self.keep_archive != null) {
            keep_archive = IfOperation{
                .condition = try allocator.dupe(u8, self.keep_archive.?.condition.?),
                .operator = try allocator.dupe(u8, self.keep_archive.?.operator.?),
                .operand = self.keep_archive.?.operand.?,
            };
        }

        var truncate_settings: ?TruncateSettings = null;
        if (self.truncate_settings != null) {
            truncate_settings = TruncateSettings{
                .from = try allocator.dupe(u8, self.truncate_settings.?.from.?),
                .by = try allocator.dupe(u8, self.truncate_settings.?.by.?),
                .size = self.truncate_settings.?.size.?,
            };
        }

        action.strategy = try allocator.dupe(u8, self.strategy);
        action.rotate_archives_dir = try utils.dupeOptString(allocator, self.rotate_archives_dir);
        action.@"if" = if (self.@"if" != null) if_operation else null;
        action.keep_archive = if (self.keep_archive != null) keep_archive else null;
        action.truncate_settings = if (self.truncate_settings != null) truncate_settings else null;
        action.compress = try utils.dupeOptString(allocator, self.compress);
        action.compression_level = self.compression_level;
        return action;
    }

    pub fn checkActionValidity(self: LogAction) !void {
        if (self.@"if" == null)
            return TaseNativeErrors.IfIsEmpty;

        _ = std.meta.stringToEnum(enums.IfConditions, self.@"if".?.condition orelse return TaseNativeErrors.MissingIfCondition) orelse return TaseNativeErrors.InvalidIfCondition;
        _ = std.meta.stringToEnum(enums.Operators, self.@"if".?.operator orelse return TaseNativeErrors.MissingIfOperator) orelse return TaseNativeErrors.InvalidIfOperator;
        if ((self.@"if".?.operand orelse return TaseNativeErrors.MissingIfOperand) < 0)
            return TaseNativeErrors.IfOperandSizeError;

        const strategy = std.meta.stringToEnum(enums.ActionStrategy, self.strategy) orelse return TaseNativeErrors.InvalidStrategy;
        switch (strategy) {
            .delete => {
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
        if (self.keep_archive != null) {
            _ = std.meta.stringToEnum(enums.IfConditions, self.keep_archive.?.condition orelse return TaseNativeErrors.MissingKeepArchiveCondition) orelse return TaseNativeErrors.InvalidRotateKeepArchiveCondition;
            _ = std.meta.stringToEnum(enums.Operators, self.keep_archive.?.operator orelse return TaseNativeErrors.MissingKeepArchiveOperator) orelse return TaseNativeErrors.InvalidRotateKeepArchiveOperator;
            if ((self.keep_archive.?.operand orelse return TaseNativeErrors.MissingKeepArchiveOperand) < 0)
                return TaseNativeErrors.KeepArhiveOpenrandSizeError;
        }

        if (self.compress != null) {
            switch (std.meta.stringToEnum(enums.CompressType, self.compress.?) orelse return TaseNativeErrors.InvalidCompressionType) {
                .gzip,
                => {
                    if (self.compression_level.? < 4 or self.compression_level.? > 9)
                        return TaseNativeErrors.CompressionLevelInvalid;
                },
            }
        }
    }

    fn checkMandatoryFieldsForTruncate(self: LogAction) !void {
        _ = self.truncate_settings orelse return TaseNativeErrors.TruncateRequiresSettings;
        _ = std.meta.stringToEnum(enums.TruncateBy, self.truncate_settings.?.by orelse return TaseNativeErrors.MissingTruncateBy) orelse return TaseNativeErrors.InvalidTruncateByFieldValue;
        _ = std.meta.stringToEnum(enums.TruncateFrom, self.truncate_settings.?.from orelse return TaseNativeErrors.MissingTruncateFrom) orelse return TaseNativeErrors.InvalidTruncateFromFieldValue;

        if ((self.truncate_settings.?.size orelse return TaseNativeErrors.MissingTruncateSize) < 1)
            return TaseNativeErrors.TruncateSizeError;
    }
};

pub const TruncateSettings = struct {
    from: ?[]const u8 = null,
    by: ?[]const u8 = null,
    size: ?i32 = null,
};

pub const IfOperation = struct {
    condition: ?[]const u8 = null,
    operator: ?[]const u8 = null,
    operand: ?i32 = null,
};

pub const MasterServerConf = struct {
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
test "isValidYamlTest" {
    var as = [_][]const u8{ "test", "local" };
    var as_undefined = [_][]const u8{ "test", "test2" };
    var agents = [_]Agent{
        Agent{
            .hostname = "remotehost",
            .name = "test",
            .port = 7424,
            .secret = "78asd6n7a8sd6hsa8a978ns6md78as6d",
        },
    };
    var agent_name_local = [_]Agent{
        Agent{
            .hostname = "remotehost",
            .name = "local",
            .port = 7424,
            .secret = "78asd6n7a8sd6hsa8a978ns6md78as6d",
        },
        Agent{
            .hostname = "testhost",
            .name = "test",
            .port = 7424,
            .secret = "78asd6n7a8sd6hsa8a978ns6md78as6d",
        },
    };
    var duplicate_agents_hostname = [_]Agent{
        Agent{
            .hostname = "remotehost",
            .name = "test",
            .port = 7424,
            .secret = "78asd6n7a8sd6hsa8a978ns6md78as6d",
        },
        Agent{
            .hostname = "remotehost",
            .name = "asdsa",
            .port = 1232,
            .secret = "98asj76d89as67d897sa67s",
        },
    };
    var duplicate_agents_name = [_]Agent{
        Agent{
            .hostname = "remotehost",
            .name = "test",
            .port = 7424,
            .secret = "78asd6n7a8sd6hsa8a978ns6md78as6d",
        },
        Agent{
            .hostname = "sometotherhost",
            .name = "test",
            .port = 1232,
            .secret = "98asj76d89as67d897sa67s",
        },
    };
    var configs = [_]LogConf{
        LogConf{
            .app_name = "test",
            .cron_expression = "5 4 * * *",
            .log_files_regexp = "test.log",
            .logs_dir = "/var/log/tase",
            .run_agent_names = &as,
            .action = LogAction{
                .strategy = "delete",
                .@"if" = IfOperation{
                    .condition = "days",
                    .operator = ">",
                    .operand = 2,
                },
            },
        },
    };
    var configs_undefined_agent_name = [_]LogConf{
        LogConf{
            .app_name = "test",
            .cron_expression = "5 4 * * *",
            .log_files_regexp = "test.log",
            .logs_dir = "/var/log/tase",
            .run_agent_names = &as_undefined,
            .action = LogAction{
                .strategy = "delete",
                .@"if" = IfOperation{
                    .condition = "days",
                    .operator = ">",
                    .operand = 2,
                },
            },
        },
    };
    const TestCase = struct {
        yaml_cfg: YamlCfgContainer,
        err: ?anyerror = null,
    };
    var tcs = [_]TestCase{
        .{
            .yaml_cfg = YamlCfgContainer{
                .agents = &agents,
                .server = MasterServerConf{
                    .host = "localhost",
                    .port = 7424,
                    .time_zone = "Asia/Nicosia",
                    .type = "tcp",
                },
                .configs = &configs,
            },
        },
        .{
            .yaml_cfg = YamlCfgContainer{
                .agents = &agents,
                .server = MasterServerConf{
                    .host = "localhost",
                    .port = 7424,
                    .time_zone = "Asia/Nicosia",
                    .type = "tcp",
                },
                .configs = &configs_undefined_agent_name,
            },
            .err = TaseNativeErrors.UndefinedAgent,
        },
        .{
            .yaml_cfg = YamlCfgContainer{
                .agents = &duplicate_agents_hostname,
                .server = MasterServerConf{
                    .host = "localhost",
                    .port = 7424,
                    .time_zone = "Asia/Nicosia",
                    .type = "tcp",
                },
                .configs = &configs,
            },
            .err = TaseNativeErrors.DuplicateAgentHostName,
        },
        .{
            .yaml_cfg = YamlCfgContainer{
                .agents = &duplicate_agents_name,
                .server = MasterServerConf{
                    .host = "localhost",
                    .port = 7424,
                    .time_zone = "Asia/Nicosia",
                    .type = "tcp",
                },
                .configs = &configs,
            },
            .err = TaseNativeErrors.DuplicateAgentName,
        },
        .{
            .yaml_cfg = YamlCfgContainer{
                .agents = &agent_name_local,
                .server = MasterServerConf{
                    .host = "localhost",
                    .port = 7424,
                    .time_zone = "Asia/Nicosia",
                    .type = "tcp",
                },
                .configs = &configs,
            },
            .err = TaseNativeErrors.LocalAgentNameIsReserved,
        },
    };

    for (&tcs) |case| {
        if (case.err != null)
            try testing.expectError(case.err.?, case.yaml_cfg.isValidYaml(testing.allocator))
        else
            try case.yaml_cfg.isValidYaml(testing.allocator);
    }
}
test "isConfigValidTest" {
    var a3 = [_][]const u8{ "Hello", "Foo", "Bar" };
    const TestCase = struct {
        log_conf: LogConf,
        err: ?anyerror = null,
    };
    var tcs = [_]TestCase{
        .{
            .log_conf = LogConf{
                .app_name = "test",
                .cron_expression = "0",
                .log_files_regexp = "test.log",
                .logs_dir = "/var/log/tase",
                .run_agent_names = &a3,
                .action = LogAction{
                    .strategy = "truncate",
                },
            },
            .err = error.InvalidLength,
        },
        .{
            .log_conf = LogConf{
                .app_name = "test",
                .cron_expression = "5 4 * * *",
                .log_files_regexp = "test.log",
                .logs_dir = "/var/log/tase",
                .run_agent_names = &a3,
                .action = LogAction{
                    .strategy = "truncate",
                },
            },
            .err = TaseNativeErrors.IfIsEmpty,
        },
        .{
            .log_conf = LogConf{
                .app_name = "test",
                .cron_expression = "5 4 * * *",
                .log_files_regexp = "s([wD.log",
                .logs_dir = "/var/log/tase",
                .run_agent_names = &a3,
                .action = LogAction{
                    .strategy = "truncate",
                },
            },
            .err = error.compile,
        },
        .{
            .log_conf = LogConf{
                .app_name = "test",
                .cron_expression = "5 4 * * *",
                .log_files_regexp = "test.log",
                .logs_dir = "/var/log/tase",
                .run_agent_names = &a3,
                .action = LogAction{
                    .strategy = "delete",
                    .@"if" = IfOperation{
                        .condition = "days",
                        .operator = ">",
                        .operand = 2,
                    },
                },
            },
        },
    };

    for (&tcs) |case| {
        if (case.err != null)
            try testing.expectError(case.err.?, case.log_conf.isConfigValid(testing.allocator))
        else
            try case.log_conf.isConfigValid(testing.allocator);
    }
}

test "LogActionDupeTest" {
    const TestCase = struct {
        log_action: LogAction,
    };
    var tcs = [_]TestCase{
        .{
            .log_action = LogAction{
                .strategy = "non-valid-strategy",
            },
        },
        .{
            .log_action = LogAction{
                .strategy = "non-valid-strategy",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .keep_archive = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .truncate_settings = TruncateSettings{
                    .by = "size",
                    .from = "bottom",
                    .size = 1024,
                },
            },
        },
    };
    for (&tcs) |case| {
        const alloc = testing.allocator;
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        _ = try case.log_action.dupe(arena.allocator());
    }
}

test "checkActionValidityTest" {
    const TestCase = struct {
        log_action: LogAction,
        err: ?anyerror = null,
    };
    var tcs = [_]TestCase{
        .{
            .log_action = LogAction{
                .strategy = "non-valid-strategy",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
            },
            .err = TaseNativeErrors.InvalidStrategy,
        },
        .{
            .log_action = LogAction{ .strategy = "delete" },
            .err = TaseNativeErrors.IfIsEmpty,
        },
        .{
            .log_action = LogAction{
                .strategy = "delete",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operator = ">",
                },
            },
            .err = TaseNativeErrors.MissingIfOperand,
        },
        .{
            .log_action = LogAction{
                .strategy = "delete",
                .@"if" = IfOperation{ .condition = "size", .operator = ">", .operand = -1 },
            },
            .err = TaseNativeErrors.IfOperandSizeError,
        },
        .{
            .log_action = LogAction{
                .strategy = "delete",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                },
            },
            .err = TaseNativeErrors.MissingIfOperator,
        },
        .{
            .log_action = LogAction{
                .strategy = "delete",
                .@"if" = IfOperation{
                    .operand = 2,
                    .operator = ">",
                },
            },
            .err = TaseNativeErrors.MissingIfCondition,
        },
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
            },
        },
        .{
            .log_action = LogAction{
                .strategy = "delete",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
            },
        },
        .{
            .log_action = LogAction{
                .strategy = "truncate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
            },
            .err = TaseNativeErrors.TruncateRequiresSettings,
        },
        .{
            .log_action = LogAction{
                .strategy = "truncate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .truncate_settings = TruncateSettings{
                    .by = "line",
                    .from = "top",
                    .size = 100,
                },
            },
        },
    };

    for (&tcs) |case| {
        if (case.err != null)
            try testing.expectError(case.err.?, case.log_action.checkActionValidity())
        else
            try case.log_action.checkActionValidity();
    }
}

test "checkMandatoryFieldsForRotateTest" {
    const TestCase = struct {
        log_action: LogAction,
        err: ?anyerror = null,
    };
    var tcs = [_]TestCase{
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
            },
        },
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .keep_archive = IfOperation{
                    .condition = "size",
                    .operand = 2,
                },
            },
            .err = TaseNativeErrors.MissingKeepArchiveOperator,
        },
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .keep_archive = IfOperation{
                    .condition = "size",
                    .operator = ">",
                },
            },
            .err = TaseNativeErrors.MissingKeepArchiveOperand,
        },
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .keep_archive = IfOperation{
                    .condition = "size",
                    .operator = ">",
                    .operand = -1,
                },
            },
            .err = TaseNativeErrors.KeepArhiveOpenrandSizeError,
        },
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .keep_archive = IfOperation{
                    .operand = 2,
                    .operator = ">",
                },
            },
            .err = TaseNativeErrors.MissingKeepArchiveCondition,
        },
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .keep_archive = IfOperation{
                    .condition = "invalid-condition",
                    .operand = 2,
                    .operator = ">",
                },
            },
            .err = TaseNativeErrors.InvalidRotateKeepArchiveCondition,
        },
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .keep_archive = IfOperation{
                    .condition = "days",
                    .operand = 2,
                    .operator = "invalid-operator",
                },
            },
            .err = TaseNativeErrors.InvalidRotateKeepArchiveOperator,
        },
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .keep_archive = IfOperation{
                    .condition = "days",
                    .operand = 2,
                    .operator = ">",
                },
                .compress = "gzip",
            },
        },
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .keep_archive = IfOperation{
                    .condition = "days",
                    .operand = 2,
                    .operator = ">",
                },
                .compress = "invalid-compression-type",
            },
            .err = TaseNativeErrors.InvalidCompressionType,
        },
        .{
            .log_action = LogAction{
                .strategy = "rotate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .keep_archive = IfOperation{
                    .condition = "days",
                    .operand = 2,
                    .operator = ">",
                },
                .compress = "gzip",
                .compression_level = 2,
            },
            .err = TaseNativeErrors.CompressionLevelInvalid,
        },
    };

    for (&tcs) |case| {
        if (case.err != null)
            try testing.expectError(case.err.?, case.log_action.checkActionValidity())
        else
            try case.log_action.checkActionValidity();
    }
}

test "checkMandatoryFieldsForTruncateTest" {
    const TestCase = struct {
        log_action: LogAction,
        err: ?anyerror = null,
    };
    var tcs = [_]TestCase{
        .{
            .log_action = LogAction{
                .strategy = "truncate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
            },
            .err = TaseNativeErrors.TruncateRequiresSettings,
        },
        .{
            .log_action = LogAction{
                .strategy = "truncate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .truncate_settings = TruncateSettings{
                    .size = 1,
                    .from = "top",
                },
            },
            .err = TaseNativeErrors.MissingTruncateBy,
        },
        .{
            .log_action = LogAction{
                .strategy = "truncate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .truncate_settings = TruncateSettings{
                    .size = 1,
                    .by = "size",
                },
            },
            .err = TaseNativeErrors.MissingTruncateFrom,
        },
        .{
            .log_action = LogAction{
                .strategy = "truncate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .truncate_settings = TruncateSettings{
                    .from = "bottom",
                    .by = "size",
                },
            },
            .err = TaseNativeErrors.MissingTruncateSize,
        },
        .{
            .log_action = LogAction{
                .strategy = "truncate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .truncate_settings = TruncateSettings{
                    .from = "bottom",
                    .by = "size",
                    .size = 0,
                },
            },
            .err = TaseNativeErrors.TruncateSizeError,
        },
        .{
            .log_action = LogAction{
                .strategy = "truncate",
                .@"if" = IfOperation{
                    .condition = "size",
                    .operand = 2,
                    .operator = ">",
                },
                .truncate_settings = TruncateSettings{
                    .from = "bottom",
                    .by = "size",
                    .size = 1,
                },
            },
        },
    };

    for (&tcs) |case| {
        if (case.err != null)
            try testing.expectError(case.err.?, case.log_action.checkActionValidity())
        else
            try case.log_action.checkActionValidity();
    }
}
