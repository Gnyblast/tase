const std = @import("std");

const TaseError = struct {
    err: anyerror,
    message: []const u8,
};

pub fn getLogMessageByErr(erro: anyerror) []const u8 {
    inline for (errors) |err| {
        if (erro == err.err) {
            return err.message;
        }
    }

    return "Unknown error occured";
}

pub const errors = [_]TaseError{
    .{
        .err = error.SecretIsMandatory,
        .message = "--secret is mandatory for agent type runs",
    },
    .{
        .err = error.MasterOrAgent,
        .message = "either --master or --agent should be passed",
    },
    .{
        .err = error.OnlyMasterOrAgent,
        .message = "both --master and --agent flag is not allowed together",
    },
    .{
        .err = error.MasterHostRequired,
        .message = "--master-host is mandatory for agents",
    },
    .{
        .err = error.MasterPortRequired,
        .message = "--master-port is mandatory for agents",
    },
    .{
        .err = error.InvalidServerType,
        .message = "server type is not valid",
    },
    .{
        .err = error.InvalidStrategy,
        .message = "strategy is invalid in the configs",
    },
    .{
        .err = error.DuplicateAgentName,
        .message = "duplicated agent name",
    },
    .{
        .err = error.DuplicateAgentHostName,
        .message = "duplicated agent hostname",
    },
    .{
        .err = error.UndefinedAgent,
        .message = "agent in configuration is not a valid agent",
    },
    .{
        .err = error.CronCannotBeUndefined,
        .message = "cron expression cannot be undefined for a config",
    },
    .{
        .err = error.NDaysOldRequired,
        .message = "delete/rotate config required \"n_day_old\" field to set to a number",
    },
    .{
        .err = error.CompressionTypeMandatory,
        .message = "compression type is mandatory for rotate",
    },
    .{
        .err = error.CompressionLevelMandatory,
        .message = "compression level is mandatory for rotate",
    },
    .{
        .err = error.InvalidCompressioType,
        .message = "compression type is invalid",
    },
    .{
        .err = error.TruncateRequiresByField,
        .message = "truncate strategy requires \"by\" field to set",
    },
    .{
        .err = error.InvalidByFieldValue,
        .message = "\"by\" filed value is invalid",
    },
    .{
        .err = error.TruncateRequiresFromField,
        .message = "truncate strategy requires \"from\" field to set",
    },
    .{
        .err = error.InvalidFromFieldValue,
        .message = "\"from\" filed value is invalid",
    },
    .{
        .err = error.NotValidAgentHostname,
        .message = "hostname is not valid for any agents",
    },
};
