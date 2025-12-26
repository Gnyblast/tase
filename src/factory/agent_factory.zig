const std = @import("std");
const testing = std.testing;
const tcp = @import("../agent/tcp.zig");
const configs = @import("../app/config.zig");
const datetime = @import("datetime").datetime;

const Allocator = std.mem.Allocator;
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;

pub const ServerTypes = enum { tcp, tls };

pub fn getAgent(allocator: Allocator, server: []const u8, host: []const u8, port: u16, secret: []const u8) !Agent {
    const server_type = std.meta.stringToEnum(ServerTypes, server) orelse {
        return TaseNativeErrors.InvalidServerType;
    };

    switch (server_type) {
        .tcp => {
            return try tcp.TCPAgent.create(allocator, host, port, secret);
        },
        else => return TaseNativeErrors.InvalidServerType,
    }
}

pub const Agent = struct {
    ptr: *anyopaque,
    sendLogConfFn: *const fn (ptr: *anyopaque, allocator: Allocator, cfg: configs.LogConf, timezone: datetime.Timezone) anyerror!void,
    destroyFn: *const fn (ptr: *anyopaque, allocator: Allocator) void,
    //test-no-cover-start
    pub fn sendLogConf(self: Agent, allocator: Allocator, cfg: configs.LogConf, timezone: datetime.Timezone) !void {
        return self.sendLogConfFn(self.ptr, allocator, cfg, timezone);
    }
    //test-no-cover-end

    pub fn destroy(self: Agent, allocator: Allocator) void {
        return self.destroyFn(self.ptr, allocator);
    }
};

test "getAgentTest" {
    const allocator = testing.allocator;
    const agent = try getAgent(allocator, "tcp", "localhost", 7424, "test");
    defer agent.destroy(allocator);

    const agent_err = getAgent(testing.allocator, "tls", "localhost", 7424, "test");
    try testing.expectError(TaseNativeErrors.InvalidServerType, agent_err);
}
