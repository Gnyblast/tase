const std = @import("std");
const testing = std.testing;
const tcp = @import("../server/tcp.zig");
const configs = @import("../app/config.zig");

const Allocator = std.mem.Allocator;
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;

const ServerTypes = enum { tcp, tls };

pub fn getServer(allocator: Allocator, server: []const u8, host: []const u8, port: u16, secret: []const u8) !Server {
    const server_type = std.meta.stringToEnum(ServerTypes, server) orelse {
        return TaseNativeErrors.InvalidServerType;
    };

    switch (server_type) {
        .tcp => {
            return try tcp.TCPServer.create(allocator, host, port, secret);
        },
        else => return TaseNativeErrors.InvalidServerType,
    }
}

pub const Server = struct {
    ptr: *anyopaque,
    startAgentServerFn: *const fn (ptr: *anyopaque) anyerror!void,
    startMasterServerFn: *const fn (ptr: *anyopaque) anyerror!void,
    setAgentsFn: *const fn (ptr: *anyopaque, agents: []configs.Agent) void,
    destroyFn: *const fn (ptr: *anyopaque, allocator: Allocator) void,

    //test-no-cover-start
    pub fn startAgentServer(self: Server) !void {
        return self.startAgentServerFn(self.ptr);
    }

    pub fn startMasterServer(self: Server) !void {
        return self.startMasterServerFn(self.ptr);
    }

    pub fn setAgents(self: Server, agents: []configs.Agent) void {
        self.setAgentsFn(self.ptr, agents);
    }
    //test-no-cover-end

    pub fn destroy(self: Server, allocator: Allocator) void {
        return self.destroyFn(self.ptr, allocator);
    }
};

test "getServerTest" {
    const allocator = testing.allocator;
    const server = try getServer(allocator, "tcp", "localhost", 7424, "test");
    defer server.destroy(allocator);

    const server_err = getServer(testing.allocator, "tls", "localhost", 7424, "test");
    try testing.expectError(TaseNativeErrors.InvalidServerType, server_err);
}
