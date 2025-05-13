const std = @import("std");
const testing = std.testing;

pub const TaseNativeErrors = error{
    DuplicateAgentName,
    DuplicateAgentHostName,
    LocalAgentNameIsReserved,
    UndefinedAgent,
    IfIsEmpty,
    MissingIfCondition,
    InvalidIfCondition,
    MissingIfOperator,
    InvalidIfOperator,
    MissingIfOperand,
    IfOperandSizeError,
    InvalidStrategy,
    MissingKeepArchiveCondition,
    InvalidRotateKeepArchiveCondition,
    MissingKeepArchiveOperator,
    InvalidRotateKeepArchiveOperator,
    MissingKeepArchiveOperand,
    KeepArhiveOpenrandSizeError,
    CompressionLevelInvalid,
    InvalidCompressioType,
    TruncateRequiresSettings,
    MissingTruncateBy,
    InvalidTruncateByFieldValue,
    InvalidTruncateFromFieldValue,
    MissingTruncateFrom,
    MissingTruncateSize,
    TruncateSizeError,
    SecretIsMandatory,
    MasterOrAgent,
    OnlyMasterOrAgent,
    MasterHostRequired,
    MasterPortRequired,
    InvalidServerType,
    NotValidAgentHostname,
    NoAgentsFound,
};

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
        .err = TaseNativeErrors.DuplicateAgentName,
        .message = "Duplicated agent name",
    },
    .{
        .err = TaseNativeErrors.DuplicateAgentHostName,
        .message = "Duplicated agent hostname",
    },
    .{
        .err = TaseNativeErrors.LocalAgentNameIsReserved,
        .message = "\"local\" as agent name is reserved for master served itself",
    },
    .{
        .err = TaseNativeErrors.UndefinedAgent,
        .message = "Agent in configuration is not a valid agent",
    },
    .{
        .err = TaseNativeErrors.IfIsEmpty,
        .message = "If condition must be set for each log action",
    },
    .{
        .err = TaseNativeErrors.MissingIfCondition,
        .message = "Missing \"condition\" in \"if\"",
    },
    .{
        .err = TaseNativeErrors.InvalidIfCondition,
        .message = "Value for \"if.condition\" field in invalid",
    },
    .{
        .err = TaseNativeErrors.MissingIfOperator,
        .message = "Missing \"operator\" in \"if\"",
    },
    .{
        .err = TaseNativeErrors.InvalidIfOperator,
        .message = "Value for \"if.operator\" field is invalid",
    },
    .{
        .err = TaseNativeErrors.MissingIfOperand,
        .message = "Missing \"operand\" in \"if\"",
    },
    .{
        .err = TaseNativeErrors.IfOperandSizeError,
        .message = "Value for \"if.operand\" cannot be less than 0",
    },
    .{
        .err = TaseNativeErrors.InvalidStrategy,
        .message = "strategy is invalid in the configs",
    },
    .{
        .err = TaseNativeErrors.MissingKeepArchiveCondition,
        .message = "Missing \"condition\" in \"keep_archive\"",
    },
    .{
        .err = TaseNativeErrors.InvalidRotateKeepArchiveCondition,
        .message = "Value for \"keep_archive.condition\" field in rotate is invalid",
    },
    .{
        .err = TaseNativeErrors.MissingKeepArchiveOperator,
        .message = "Missing \"operator\" in \"keep_archive\"",
    },
    .{
        .err = TaseNativeErrors.InvalidRotateKeepArchiveOperator,
        .message = "Value for \"keep_archive.operator\" field in rotate is invalid",
    },
    .{
        .err = TaseNativeErrors.MissingKeepArchiveOperand,
        .message = "Missing \"operand\" in \"keep_archive\"",
    },
    .{
        .err = TaseNativeErrors.KeepArhiveOpenrandSizeError,
        .message = "Value for \"keep_archive.operand\" cannot be less than 0",
    },
    .{
        .err = TaseNativeErrors.CompressionLevelInvalid,
        .message = "Compression levels are starting from 4 goes up to 9",
    },
    .{
        .err = TaseNativeErrors.InvalidCompressioType,
        .message = "compression type is invalid",
    },
    .{
        .err = TaseNativeErrors.TruncateRequiresSettings,
        .message = "\"truncate\" strategy requires \"truncate_settings\"",
    },
    .{
        .err = TaseNativeErrors.MissingTruncateBy,
        .message = "Missing \"by\" in \"truncate_setting\"",
    },
    .{
        .err = TaseNativeErrors.InvalidTruncateByFieldValue,
        .message = "\"by\" filed value in \"truncate_settings\" is invalid",
    },
    .{
        .err = TaseNativeErrors.InvalidTruncateFromFieldValue,
        .message = "\"from\" filed value in \"truncate_settings\" is invalid",
    },
    .{
        .err = TaseNativeErrors.MissingTruncateFrom,
        .message = "Missing \"from\" in \"truncate_setting\"",
    },
    .{
        .err = TaseNativeErrors.MissingTruncateSize,
        .message = "Value for \"truncata_settings.size\" cannot be less than 1",
    },
    .{
        .err = TaseNativeErrors.TruncateSizeError,
        .message = "\"size\" in \"truncate_settings\" must be greater than 0",
    },
    .{
        .err = TaseNativeErrors.SecretIsMandatory,
        .message = "--secret cli arg or TASE_AGENT_SECRET env var is mandatory for agent type runs",
    },
    .{
        .err = TaseNativeErrors.MasterOrAgent,
        .message = "either --master or --agent should be passed",
    },
    .{
        .err = TaseNativeErrors.OnlyMasterOrAgent,
        .message = "both --master and --agent flag is not allowed together",
    },
    .{
        .err = TaseNativeErrors.MasterHostRequired,
        .message = "--master-host is mandatory for agents",
    },
    .{
        .err = TaseNativeErrors.MasterPortRequired,
        .message = "--master-port is mandatory for agents",
    },
    .{
        .err = TaseNativeErrors.InvalidServerType,
        .message = "server type is not valid",
    },
    .{
        .err = TaseNativeErrors.NotValidAgentHostname,
        .message = "hostname is not valid for any agents",
    },
    .{
        .err = TaseNativeErrors.NoAgentsFound,
        .message = "No matching agents found",
    },
};

test "getLogMessageByErrTest" {
    const TestCase = struct {
        err: anyerror,
        expected: []const u8,
        is_alloc: bool,
    };

    const tcs = [_]TestCase{
        .{
            .err = TaseNativeErrors.NoAgentsFound,
            .expected = "No matching agents found",
            .is_alloc = false,
        },
        .{
            .err = error.TestError,
            .expected = "error: error.TestError",
            .is_alloc = true,
        },
    };

    for (&tcs) |tc| {
        var allocator = testing.allocator;
        const err_msg = getLogMessageByErr(allocator, tc.err);
        defer if (err_msg.allocated) allocator.free(err_msg.message);
        try testing.expectEqualDeep(tc.expected, err_msg.message);
        try testing.expectEqual(tc.is_alloc, err_msg.allocated);
    }
}
