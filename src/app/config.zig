const std = @import("std");
const enums = @import("./enum.zig");
const Allocator = std.mem.Allocator;

pub const Tesa = struct {
    configs: std.ArrayList(LogConf),

    pub fn init(allocator: Allocator) Tesa {
        const arr_list = std.ArrayList(LogConf).init(allocator);
        return Tesa{
            .configs = arr_list,
        };
    }
    pub fn AddConf(self: *Tesa, conf: LogConf) !void {
        try self.configs.append(conf);
    }

    pub fn deinit(self: *Tesa) void {
        self.configs.deinit();
    }
};

pub const LogConf = struct {
    app_name: []const u8,
    log_path: []const u8,
    cron_expression: []const u8,
    run_agent: []const u8,
    action: LogAction,
};

const LogAction = struct {
    type: []const u8,
    from: []const u8,
    by: []const u8,
    size: u32 = 1024,
};
