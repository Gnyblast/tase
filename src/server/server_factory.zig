const std = @import("std");
const tcp = @import("./tcp.zig");

const Allocator = std.mem.Allocator;

const ServerTypes = enum { tcp, tls };

pub fn getServer(allocator: Allocator, server: []const u8, host: []const u8, port: u16) !Server {
    const server_type = std.meta.stringToEnum(ServerTypes, server) orelse {
        return error.InvalidServerType;
    };

    switch (server_type) {
        .tcp => {
            return try tcp.TCPServer.create(allocator, host, port);
        },
        else => return error.InvalidServerType,
    }
}

pub const Server = struct {
    ptr: *anyopaque,
    startServerFn: *const fn (ptr: *anyopaque) anyerror!void,
    destroyFn: *const fn (ptr: *anyopaque, allocator: Allocator) void,

    pub fn startServer(self: Server) !void {
        return self.startServerFn(self.ptr);
    }

    pub fn destroy(self: Server, allocator: Allocator) void {
        return self.destroyFn(self.ptr, allocator);
    }
};
