const std = @import("std");
const tcp = @import("./tcp.zig");

const Allocator = std.mem.Allocator;

const ServerTypes = enum { tcp, tls };

pub fn getServer(server: []const u8, host: []const u8, port: u16, secret: ?[]const u8) !Server {
    const server_type = std.meta.stringToEnum(ServerTypes, server) orelse {
        return error.InvalidServerType;
    };

    switch (server_type) {
        .tcp => {
            var tcp_server = tcp.TCPServer.init(host, port, secret.?);
            return tcp_server.getServer();
        },
        else => return error.InvalidServerType,
    }
}

pub const Server = struct {
    ptr: *anyopaque,
    startServerFn: *const fn (ptr: *anyopaque) anyerror!void,

    pub fn startServer(self: Server) !void {
        return self.startServerFn(self.ptr);
    }
};
