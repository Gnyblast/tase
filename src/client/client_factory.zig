const std = @import("std");
const tcp = @import("./tcp.zig");
const configs = @import("../app/config.zig");

const Allocator = std.mem.Allocator;

const ServerTypes = enum { tcp, tls };

pub fn getClient(allocator: Allocator, server: []const u8, host: []const u8, port: u16, secret: []const u8) !Client {
    const server_type = std.meta.stringToEnum(ServerTypes, server) orelse {
        return error.InvalidServerType;
    };

    switch (server_type) {
        .tcp => {
            return try tcp.TCPClient.create(allocator, host, port, secret);
        },
        else => return error.InvalidServerType,
    }
}

pub const Client = struct {
    ptr: *anyopaque,
    sendMessageFn: *const fn (ptr: *anyopaque, message: *configs.LogConf, allocator: Allocator) anyerror!void,
    destroyFn: *const fn (ptr: *anyopaque, allocator: Allocator) void,

    pub fn sendMessage(self: Client, message: *configs.LogConf, allocator: Allocator) !void {
        return self.sendMessageFn(self.ptr, message, allocator);
    }

    pub fn destroy(self: Client, allocator: Allocator) void {
        return self.destroyFn(self.ptr, allocator);
    }
};
