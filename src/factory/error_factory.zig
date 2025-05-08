const std = @import("std");

const TaseError = struct {
    err: anyerror,
    message: []const u8,
};

pub const ErrorMessage = struct {
    message: []const u8,
    allocated: bool = false,
};

pub fn getLogMessageByErr(alloc: std.mem.Allocator, erro: anyerror) ErrorMessage {
    inline for (errors) |err| {
        if (erro == err.err) {
            return ErrorMessage{ .message = err.message };
        }
    }

    const msg = std.fmt.allocPrint(alloc, "error: {}", .{erro}) catch {
        return ErrorMessage{ .message = "Unknown error" };
    };

    return ErrorMessage{ .message = msg, .allocated = true };
}

//TODO: recheck errors
pub const errors = [_]TaseError{
    .{
        .err = error.SecretIsMandatory,
        .message = "--secret cli arg or TASE_AGENT_SECRET env var is mandatory for agent type runs",
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
        .err = error.NoAgentsFound,
        .message = "No matching agents found",
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
        .err = error.lineOrSizeError,
        .message = "Either \"line\" or \"size\" should be defined for truncate",
    },
    .{
        .err = error.TruncateRequiresFromField,
        .message = "truncate strategy requires \"from\" field to set",
    },
    .{
        .err = error.TruncateRequiresSettings,
        .message = "\"truncate\" strategy requires \"truncate_settings\"",
    },
    .{
        .err = error.InvalidTruncateFromFieldValue,
        .message = "\"from\" filed value in \"truncate_settings\" is invalid",
    },
    .{
        .err = error.InvalidTruncateByFieldValue,
        .message = "\"by\" filed value in \"truncate_settings\" is invalid",
    },
    .{
        .err = error.TruncateSizeError,
        .message = "\"size\" in \"truncate_settings\" must be greater than 0",
    },
    .{
        .err = error.NotValidAgentHostname,
        .message = "hostname is not valid for any agents",
    },
    .{
        .err = error.SizeIsRequiredForRotate,
        .message = "rotate strategy requires \"size\" field to set",
    },
    .{
        .err = error.SizeIsRequiredForTruncate,
        .message = "truncate strategy requires \"size\" field to set",
    },
    .{
        .err = error.RotateRequiresByField,
        .message = "rotate strategy requires \"by\" field to set",
    },
    .{
        .err = error.InvalidIfCondition,
        .message = "value for \"if.condition\" field in invalid",
    },
    .{
        .err = error.InvalidIfOperator,
        .message = "value for \"if.operator\" field is invalid",
    },
    .{
        .err = error.InvalidRotateKeepArchiveCondition,
        .message = "value for \"keep_archive.condition\" field in rotate is invalid",
    },
    .{
        .err = error.InvalidRotateKeepArchiveOperator,
        .message = "value for \"keep_archive.operator\" field in rotate is invalid",
    },
    .{
        .err = error.compile,
        .message = "Some of the regex is not valid and cannot be compiled",
    },
    .{
        .err = error.CompressionLevelInvalid,
        .message = "Compression levels are starting from 4 goes up to 9",
    },
    .{
        .err = error.LocalAgentNameIsReserved,
        .message = "\"local\" as agent name is reserved for master served itself",
    },
    .{
        .err = error.IfIsEmpty,
        .message = "If condition must be set for each log action",
    },
    .{
        .err = error.MissingIfCondition,
        .message = "Missing \"condition\" in \"if\"",
    },
    .{
        .err = error.MissingIfOperand,
        .message = "Missing \"operand\" in \"if\"",
    },
    .{
        .err = error.MissingIfOperator,
        .message = "Missing \"operator\" in \"if\"",
    },
    .{
        .err = error.MissingTruncateBy,
        .message = "Missing \"by\" in \"truncate_setting\"",
    },
    .{
        .err = error.MissingTruncateFrom,
        .message = "Missing \"from\" in \"truncate_setting\"",
    },
    .{
        .err = error.MissingKeepArchiveCondition,
        .message = "Missing \"condition\" in \"keep_archive\"",
    },
    .{
        .err = error.MissingKeepArchiveOperand,
        .message = "Missing \"operand\" in \"keep_archive\"",
    },
    .{
        .err = error.MissingKeepArchiveOperator,
        .message = "Missing \"operator\" in \"keep_archive\"",
    },
};
