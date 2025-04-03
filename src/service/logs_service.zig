const std = @import("std");
const configs = @import("../app/config.zig");
const enums = @import("../enum/config_enum.zig");

const LogService = struct {
    file: []const u8,
    log_action: configs.LogAction,

    pub fn run(self: LogService) !void {
        switch (std.meta.stringToEnum(enums.ActionStrategy, self.log_action.strategy) orelse return error.InvalidStrategy) {
            enums.ActionStrategy.delete => return doDelete(),
            enums.ActionStrategy.rotate => return doRotate(),
            enums.ActionStrategy.truncate => return doTruncate(),
        }
    }

    fn doRotate(_: LogService) !void {}

    fn doDelete(_: LogService) !void {}

    fn doTruncate(_: LogService) !void {}
};
