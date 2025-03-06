const std = @import("std");
const jwt = @import("jwt");
const net = std.net;
const posix = std.posix;
const configs = @import("../app/config.zig");

const Allocator = std.mem.Allocator;

const serverFactory = @import("./server_factory.zig");

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

    fn createTCPServer(self: TCPServer) !posix.socket_t {
        const address = try net.Address.parseIp(self.host, self.port);
        const tpe: u32 = posix.SOCK.STREAM;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.any.family, tpe, protocol);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, 128);

        return listener;
    }

    fn startAgentServer(ptr: *anyopaque) !void {
        const self: *TCPServer = @ptrCast(@alignCast(ptr));

        const listener = try self.createTCPServer();
        defer posix.close(listener);

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        while (true) {
            var client_address: net.Address = undefined;
            var client_address_len: posix.socklen_t = @sizeOf(net.Address);
            const socket = posix.accept(listener, &client_address.any, &client_address_len, 0) catch |err| {
                // Rare that this happens, but in later parts we'll
                // see examples where it does.
                std.log.scoped(.server).debug("error accept: {}", .{err});
                continue;
            };
            defer posix.close(socket);

            std.log.scoped(.server).debug("{} connected", .{client_address});

            var buf: [4096]u8 = undefined;
            const read = posix.read(socket, &buf) catch |err| {
                std.log.scoped(.server).err("error reading: {}", .{err});
                continue;
            };

            if (read == 0) {
                continue;
            }

            var arena = std.heap.ArenaAllocator.init(gpa.allocator());
            defer arena.deinit();

            var decoded = jwt.decode(arena.allocator(), configs.LogConf, buf[0..read], .{ .secret = self.secret }, .{}) catch |err| {
                std.log.scoped(.server).err("JWT Decode error: {}", .{err});
                continue;
            };
            defer decoded.deinit();

            //TODO start action in threads here
            std.log.info("{any}", .{decoded.claims});
        }
    }

    fn startMasterServer(ptr: *anyopaque) !void {
        const self: *TCPServer = @ptrCast(@alignCast(ptr));
        const listener = try self.createTCPServer();
        defer posix.close(listener);

        while (true) {
            //TODO read agent hostname
            _ = try self.getAgentSecretByHostName("");
        }
    }

    fn getAgentSecretByHostName(self: TCPServer, hostname: []const u8) ![]const u8 {
        for (self.agents.?) |agent| {
            if (std.mem.eql(u8, agent.hostname, hostname)) {
                return agent.secret;
            }
        }

        return error.NotValidAgentHostname;
    }
};
