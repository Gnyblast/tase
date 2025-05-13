const std = @import("std");
const testing = std.testing;
const tcp = @import("../client/tcp.zig");
const configs = @import("../app/config.zig");
const datetime = @import("datetime").datetime;

const Allocator = std.mem.Allocator;
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;

pub const ServerTypes = enum { tcp, tls };

pub fn getClient(allocator: Allocator, server: []const u8, host: []const u8, port: u16, secret: []const u8) !Client {
    const server_type = std.meta.stringToEnum(ServerTypes, server) orelse {
        return TaseNativeErrors.InvalidServerType;
    };

    switch (server_type) {
        .tcp => {
            return try tcp.TCPClient.create(allocator, host, port, secret);
        },
        else => return TaseNativeErrors.InvalidServerType,
    }
}

pub const Client = struct {
    ptr: *anyopaque,
    sendLogConfFn: *const fn (ptr: *anyopaque, allocator: Allocator, cfg: configs.LogConf, timezone: datetime.Timezone) anyerror!void,
    destroyFn: *const fn (ptr: *anyopaque, allocator: Allocator) void,
    //test-no-cover-start
    pub fn sendLogConf(self: Client, allocator: Allocator, cfg: configs.LogConf, timezone: datetime.Timezone) !void {
        return self.sendLogConfFn(self.ptr, allocator, cfg, timezone);
    }
    //test-no-cover-end

    pub fn destroy(self: Client, allocator: Allocator) void {
        return self.destroyFn(self.ptr, allocator);
    }
};

test "getClientTest" {
    const allocator = testing.allocator;
    const client = try getClient(allocator, "tcp", "localhost", 7424, "test");
    defer client.destroy(allocator);

    const client_err = getClient(testing.allocator, "tls", "localhost", 7424, "test");
    try testing.expectError(TaseNativeErrors.InvalidServerType, client_err);
}
