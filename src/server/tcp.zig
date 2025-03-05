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

    pub fn init(host: []const u8, port: u16) TCPServer {
        return TCPServer{ .host = host, .port = port };
    }

    pub fn getServer(self: *TCPServer) serverFactory.Server {
        return serverFactory.Server{
            .ptr = self,
            .startServerFn = startServer,
            .destroyFn = destroy,
        };
    }

    pub fn create(allocator: Allocator, host: []const u8, port: u16) !serverFactory.Server {
        const tcp = try allocator.create(TCPServer);
        tcp.* = TCPServer{ .host = host, .port = port };
        return serverFactory.Server{ .ptr = tcp, .destroyFn = destroy, .startServerFn = startServer };
    }

    fn destroy(ptr: *anyopaque, allocator: Allocator) void {
        const self: *TCPServer = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }

    fn startServer(ptr: *anyopaque) !void {
        const self: *TCPServer = @ptrCast(@alignCast(ptr));

        const address = try net.Address.parseIp(self.host, self.port);
        const tpe: u32 = posix.SOCK.STREAM;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.any.family, tpe, protocol);
        defer posix.close(listener);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, 128);

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

            var payload = std.mem.splitSequence(u8, &buf, "\n");

            var arena = std.heap.ArenaAllocator.init(gpa.allocator());
            defer arena.deinit();

            var decoded = jwt.decode(arena.allocator(), configs.LogConf, payload.first(), .{ .secret = "secret" }, .{}) catch |err| {
                std.log.scoped(.server).err("JWT Decode error: {}", .{err});
                continue;
            };
            defer decoded.deinit();

            std.log.info("{any}", .{decoded.claims});
        }
    }
};
