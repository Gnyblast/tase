const std = @import("std");
const testing = std.testing;
const jwt = @import("jwt");
const net = std.net;
const posix = std.posix;
const datetime = @import("datetime").datetime;

const Allocator = std.mem.Allocator;

const serverFactory = @import("../factory/server_factory.zig");
const configs = @import("../app/config.zig");
const Pruner = @import("../service/pruner.zig").Pruner;
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;

pub const MasterClaims = struct {
    agent_hostname: ?[]const u8,
    message: []const u8,
    exp: i64,
};

pub const AgentClaims = struct {
    agent_hostname: ?[]const u8,
    job: *const configs.LogConf,
    timezone: datetime.Timezone,
    exp: i64,
};

pub const TCPServer = struct {
    host: []const u8,
    port: u16,
    secret: []const u8,
    agents: ?[]configs.Agent,

    pub fn init(host: []const u8, port: u16, secret: []const u8) TCPServer {
        return TCPServer{
            .host = host,
            .port = port,
            .secret = secret,
            .agents = null,
        };
    }

    fn setAgents(ptr: *anyopaque, agents: []configs.Agent) void {
        const self: *TCPServer = @ptrCast(@alignCast(ptr));
        self.agents = agents;
    }

    pub fn create(allocator: Allocator, host: []const u8, port: u16, secret: []const u8) !serverFactory.Server {
        const tcp = try allocator.create(TCPServer);
        tcp.* = TCPServer.init(host, port, secret);
        return serverFactory.Server{
            .ptr = tcp,
            .destroyFn = destroy,
            .startAgentServerFn = startAgentServer,
            .startMasterServerFn = startMasterServer,
            .setAgentsFn = setAgents,
        };
    }

    fn destroy(ptr: *anyopaque, allocator: Allocator) void {
        const self: *TCPServer = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }

    fn createTCPServer(self: TCPServer, allocator: Allocator) !posix.socket_t {
        const address = try net.getAddressList(allocator, self.host, self.port);
        defer address.deinit();
        const tpe: u32 = posix.SOCK.STREAM;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.addrs[0].any.family, tpe, protocol);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.addrs[0].any, address.addrs[0].getOsSockLen());
        try posix.listen(listener, 128);

        return listener;
    }

    //test-no-cover-start
    fn startAgentServer(ptr: *anyopaque) !void {
        const self: *TCPServer = @ptrCast(@alignCast(ptr));

        var da: std.heap.DebugAllocator(.{}) = .init;
        defer {
            const leaks = da.deinit();
            std.debug.assert(leaks == .ok);
        }

        const logs_alloc = da.allocator();

        const listener = try self.createTCPServer(da.allocator());
        defer posix.close(listener);

        while (true) {
            var agent_address: net.Address = undefined;
            var agent_address_len: posix.socklen_t = @sizeOf(net.Address);
            const socket = posix.accept(listener, &agent_address.any, &agent_address_len, 0) catch |err| {
                // Rare that this happens, but in later parts we'll
                // see examples where it does.
                std.log.scoped(.server).err("error accept: {any}", .{err});
                continue;
            };
            defer posix.close(socket);

            std.log.scoped(.server).debug("{any} connected", .{agent_address});

            const timeout = posix.timeval{ .sec = 2, .usec = 500_000 };
            try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));
            try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));

            var buf: [1024]u8 = undefined;
            const read = posix.read(socket, &buf) catch |err| {
                std.log.scoped(.server).err("error reading: {any}", .{err});
                continue;
            };

            if (read == 0) {
                continue;
            }

            var arena = std.heap.ArenaAllocator.init(da.allocator());
            defer arena.deinit();

            var decoded = jwt.decode(arena.allocator(), AgentClaims, buf[0..read], .{ .secret = self.secret }, .{}) catch |err| {
                std.log.scoped(.server).err("JWT Decode error: {any}", .{err});
                continue;
            };
            defer decoded.deinit();

            // std.log.info("{any}", .{decoded.claims});
            const write = posix.write(socket, "Accepted!") catch |err| {
                std.log.scoped(.server).err("Error sending response back to master: {any}", .{err});
                continue;
            };
            if (write == 0) {
                continue;
            }

            const pruner = Pruner.create(
                logs_alloc,
                decoded.claims.timezone,
                decoded.claims.job.logs_dir,
                decoded.claims.job.log_files_regexp,
                decoded.claims.job.action,
            ) catch |err| {
                std.log.scoped(.server).err("error init logs service: {any}", .{err});
                continue;
            };

            const thread = std.Thread.spawn(.{}, Pruner.runAndDestroy, .{pruner}) catch |err| {
                std.log.scoped(.cron).err("Error while running local task on a thread: {any}", .{err});
                continue;
            };
            thread.detach();
        }
    }
    //test-no-cover-end

    //test-no-cover-start
    fn startMasterServer(ptr: *anyopaque) !void {
        const self: *TCPServer = @ptrCast(@alignCast(ptr));

        var da: std.heap.DebugAllocator(.{}) = .init;
        defer {
            const leaks = da.deinit();
            std.debug.assert(leaks == .ok);
        }

        const listener = try self.createTCPServer(da.allocator());
        defer posix.close(listener);

        const allocator = da.allocator();

        var pool: std.Thread.Pool = undefined;
        try std.Thread.Pool.init(&pool, .{ .allocator = allocator, .n_jobs = 4 });
        defer pool.deinit();

        while (true) {
            var agent_address: net.Address = undefined;
            var agent_address_len: posix.socklen_t = @sizeOf(net.Address);

            const socket = posix.accept(listener, &agent_address.any, &agent_address_len, 0) catch |err| {
                // Rare that this happens, but in later parts we'll
                // see examples where it does.
                std.log.scoped(.server).debug("error accept: {any}", .{err});
                continue;
            };

            try pool.spawn(TCPServer.runMasterSocket, .{ self, allocator, socket });
        }
    }

    fn runMasterSocket(self: *TCPServer, allocator: Allocator, socket: posix.socket_t) void {
        defer posix.close(socket);

        var buf: [1024]u8 = undefined;
        const read = posix.read(socket, &buf) catch |err| {
            std.log.scoped(.server).err("error reading: {any}", .{err});
            return;
        };

        if (read == 0) {
            return;
        }

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var decoded = jwt.decodeNoVerify(arena.allocator(), MasterClaims, buf[0..read]) catch |err| {
            std.log.scoped(.server).err("JWT Decode error: {any}", .{err});
            return;
        };
        defer decoded.deinit();
        const secret = self.getAgentSecretByHostName(decoded.claims.agent_hostname.?) catch |err| {
            std.log.scoped(.server).err("JWT Decode error: {any}", .{err});
            return;
        };

        //TODO: now decode and verify the message with correct secret used
        std.log.info("{s}", .{secret});
    }
    //test-no-cover-end

    fn getAgentSecretByHostName(self: *TCPServer, hostname: []const u8) ![]const u8 {
        for (self.agents.?) |agent| {
            if (std.mem.eql(u8, agent.hostname, hostname)) {
                return agent.secret;
            }
        }

        return TaseNativeErrors.NotValidAgentHostname;
    }
};

test "initTest" {
    const server = TCPServer.init("127.0.0.1", 7423, "supersecret");
    try testing.expectEqualStrings("127.0.0.1", server.host);
    try testing.expectEqual(@as(u16, 7423), server.port);
    try testing.expectEqualStrings("supersecret", server.secret);
    try testing.expect(server.agents == null);
}

test "createTCPServerTest" {
    const server = TCPServer.init("127.0.0.1", 7423, "supersecret");
    _ = try server.createTCPServer(testing.allocator);
}

test "setAgentsTest" {
    var server = TCPServer.init("localhost", 7423, "secret");
    var agents = [_]configs.Agent{
        .{
            .name = "agent1",
            .hostname = "agent1",
            .port = 7424,
            .secret = "secret1",
        },
        .{
            .name = "agent2",
            .hostname = "agent2",
            .port = 7424,
            .secret = "secret2",
        },
    };
    TCPServer.setAgents(@ptrCast(&server), &agents);

    try testing.expect(server.agents != null);
    try testing.expectEqual(@as(usize, 2), server.agents.?.len);
    try testing.expectEqualStrings("agent1", server.agents.?[0].hostname);
}

test "getAgentSecretByHostNameTest" {
    const TestCase = struct {
        agents: []configs.Agent,
        get_agent: []const u8,
        get_secret: []const u8,
        err: ?anyerror = null,
    };
    var agents = [_]configs.Agent{
        .{
            .name = "agent1",
            .hostname = "test-host",
            .port = 7423,
            .secret = "secret123",
        },
        .{
            .name = "agent2",
            .hostname = "another-host",
            .port = 7423,
            .secret = "456",
        },
    };
    var tcs = [_]TestCase{
        .{
            .get_agent = "test-host",
            .get_secret = "secret123",
            .agents = &agents,
        },
        .{ .get_agent = "invalidhost", .get_secret = "secret1234", .agents = &agents, .err = TaseNativeErrors.NotValidAgentHostname },
    };

    for (&tcs) |tc| {
        var server = TCPServer.init("localhost", 1234, "defaultsecret");
        TCPServer.setAgents(@ptrCast(&server), tc.agents);
        if (tc.err == null)
            try testing.expectEqualStrings(tc.get_secret, try server.getAgentSecretByHostName(tc.get_agent))
        else
            try testing.expectError(tc.err.?, server.getAgentSecretByHostName(tc.get_agent));
    }
}
