const std = @import("std");
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

    pub fn sendLogConf(self: Client, allocator: Allocator, cfg: configs.LogConf, timezone: datetime.Timezone) !void {
        return self.sendLogConfFn(self.ptr, allocator, cfg, timezone);
    }

    pub fn destroy(self: Client, allocator: Allocator) void {
        return self.destroyFn(self.ptr, allocator);
    }
};
