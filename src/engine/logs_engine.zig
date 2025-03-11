const std = @import("std");
const configs = @import("../app/config.zig");
const enums = @import("../enum/config_enum.zig");

const LogEngine = struct {
    log_action: configs.LogAction,

    pub fn run(self: LogEngine) !void {
        switch (std.meta.stringToEnum(enums.ActionStrategy, self.log_action.strategy) orelse return error.InvalidStrategy) {
            enums.ActionStrategy.delete => return doDelete(),
            enums.ActionStrategy.rotate => return doRotate(),
            enums.ActionStrategy.truncate => return doTruncate(),
        }
    }

    fn doRotate(_: LogEngine) !void {}

    fn doDelete(_: LogEngine) !void {}

    fn doTruncate(_: LogEngine) !void {}
};
