const std = @import("std");
const enums = @import("./enum.zig");
const Allocator = std.mem.Allocator;

pub const Tesa = struct {
    configs: std.ArrayList(LogConf),
    cli_args: ?argOpts = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Tesa {
        const arr_list = std.ArrayList(LogConf).init(allocator);
        return Tesa{
            .allocator = allocator,
            .configs = arr_list,
            .cli_args = null,
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

pub const argOpts = struct {
    @"logs-path": []const u8 = "/var/log/tase",

    pub const shorthands = .{
        .l = "logs-path",
    };

    pub const meta = .{
        .option_docs = .{ .@"logs-path" = "Directory path for log files of the tase app" },
    };
};
