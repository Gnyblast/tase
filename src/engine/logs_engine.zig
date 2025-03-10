const std = @import("std");
const configs = @import("../app/config.zig");

const LogEngine = struct {
    log_action: configs.LogAction,
};
