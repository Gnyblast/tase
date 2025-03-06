const std = @import("std");
const tcp = @import("./tcp.zig");
const configs = @import("../app/config.zig");

const Allocator = std.mem.Allocator;

const ServerTypes = enum { tcp, tls };

pub fn getServer(allocator: Allocator, server: []const u8, host: []const u8, port: u16, secret: []const u8) !Server {
    const server_type = std.meta.stringToEnum(ServerTypes, server) orelse {
        return error.InvalidServerType;
    };

    switch (server_type) {
        .tcp => {
            return try tcp.TCPServer.create(allocator, host, port, secret);
        },
        else => return error.InvalidServerType,
    }
}

pub const Server = struct {
    ptr: *anyopaque,
    startAgentServerFn: *const fn (ptr: *anyopaque) anyerror!void,
    startMasterServerFn: *const fn (ptr: *anyopaque) anyerror!void,
    setAgentsFn: *const fn (ptr: *anyopaque, agents: []configs.Agents) void,
    destroyFn: *const fn (ptr: *anyopaque, allocator: Allocator) void,

    pub fn startAgentServer(self: Server) !void {
        return self.startAgentServerFn(self.ptr);
    }

    pub fn startMasterServer(self: Server) !void {
        return self.startMasterServerFn(self.ptr);
    }

    pub fn setAgents(self: Server, agents: []configs.Agents) void {
        self.setAgentsFn(self.ptr, agents);
    }

    pub fn destroy(self: Server, allocator: Allocator) void {
        return self.destroyFn(self.ptr, allocator);
    }
};
