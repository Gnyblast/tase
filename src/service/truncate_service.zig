const std = @import("std");
const helper = @import("helper.zig");
const enums = @import("../enum/config_enum.zig");
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;
const Pruner = @import("./pruner.zig").Pruner;

const Allocator = std.mem.Allocator;

pub fn doTruncate(pruner: Pruner) !void {
    switch (std.meta.stringToEnum(enums.TruncateFrom, pruner.log_action.truncate_settings.?.from.?) orelse return TaseNativeErrors.InvalidTruncateFromFieldValue) {
        .bottom => {
            return truncateFromBottom(pruner);
        },
        .top => {
            return truncateFromTop(pruner);
        },
    }
}

fn truncateFromBottom(_: Pruner) void {}

fn truncateFromTop(_: Pruner) void {}
