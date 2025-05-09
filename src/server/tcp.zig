const std = @import("std");
const jwt = @import("jwt");
const net = std.net;
const posix = std.posix;
const datetime = @import("datetime").datetime;

const Allocator = std.mem.Allocator;

const serverFactory = @import("../factory/server_factory.zig");
const configs = @import("../app/config.zig");
const LogService = @import("../service/logs_service.zig").LogService;
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
    agents: ?[]configs.Agents,

    pub fn init(host: []const u8, port: u16, secret: []const u8) TCPServer {
        return TCPServer{
            .host = host,
            .port = port,
            .secret = secret,
            .agents = null,
        };
    }

    fn setAgents(ptr: *anyopaque, agents: []configs.Agents) void {
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
            var client_address: net.Address = undefined;
            var client_address_len: posix.socklen_t = @sizeOf(net.Address);
            const socket = posix.accept(listener, &client_address.any, &client_address_len, 0) catch |err| {
                // Rare that this happens, but in later parts we'll
                // see examples where it does.
                std.log.scoped(.server).err("error accept: {}", .{err});
                continue;
            };
            defer posix.close(socket);

            std.log.scoped(.server).debug("{} connected", .{client_address});

            const timeout = posix.timeval{ .sec = 2, .usec = 500_000 };
            try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));
            try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));

            var buf: [1024]u8 = undefined;
            const read = posix.read(socket, &buf) catch |err| {
                std.log.scoped(.server).err("error reading: {}", .{err});
                continue;
            };

            if (read == 0) {
                continue;
            }

            var arena = std.heap.ArenaAllocator.init(da.allocator());
            defer arena.deinit();

            var decoded = jwt.decode(arena.allocator(), AgentClaims, buf[0..read], .{ .secret = self.secret }, .{}) catch |err| {
                std.log.scoped(.server).err("JWT Decode error: {}", .{err});
                continue;
            };
            defer decoded.deinit();

            // std.log.info("{any}", .{decoded.claims});
            const write = posix.write(socket, "Accepted!") catch |err| {
                std.log.scoped(.server).err("Error sending response back to master: {}", .{err});
                continue;
            };
            if (write == 0) {
                continue;
            }

            const logsService = LogService.create(
                logs_alloc,
                decoded.claims.timezone,
                decoded.claims.job.logs_dir,
                decoded.claims.job.log_files_regexp,
                decoded.claims.job.action,
            ) catch |err| {
                std.log.scoped(.server).err("error init logs service: {}", .{err});
                continue;
            };

            const thread = std.Thread.spawn(.{}, LogService.runAndDestroy, .{logsService}) catch |err| {
                std.log.scoped(.cron).err("Error while running local task on a thread: {}", .{err});
                continue;
            };
            thread.detach();
        }
    }

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
            var client_address: net.Address = undefined;
            var client_address_len: posix.socklen_t = @sizeOf(net.Address);

            const socket = posix.accept(listener, &client_address.any, &client_address_len, 0) catch |err| {
                // Rare that this happens, but in later parts we'll
                // see examples where it does.
                std.log.scoped(.server).debug("error accept: {}", .{err});
                continue;
            };

            try pool.spawn(TCPServer.runMasterSocket, .{ self, allocator, socket });
        }
    }

    fn runMasterSocket(self: *TCPServer, allocator: Allocator, socket: posix.socket_t) void {
        defer posix.close(socket);

        var buf: [1024]u8 = undefined;
        const read = posix.read(socket, &buf) catch |err| {
            std.log.scoped(.server).err("error reading: {}", .{err});
            return;
        };

        if (read == 0) {
            return;
        }

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var decoded = jwt.decodeNoVerify(arena.allocator(), MasterClaims, buf[0..read]) catch |err| {
            std.log.scoped(.server).err("JWT Decode error: {}", .{err});
            return;
        };
        defer decoded.deinit();
        const secret = self.getAgentSecretByHostName(decoded.claims.agent_hostname.?) catch |err| {
            std.log.scoped(.server).err("JWT Decode error: {}", .{err});
            return;
        };

        //TODO: now decode and verify the message with correct secret used
        std.log.info("{s}", .{secret});
    }

    fn getAgentSecretByHostName(self: *TCPServer, hostname: []const u8) ![]const u8 {
        for (self.agents.?) |agent| {
            if (std.mem.eql(u8, agent.hostname, hostname)) {
                return agent.secret;
            }
        }

        return TaseNativeErrors.NotValidAgentHostname;
    }
};
