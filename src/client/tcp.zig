const std = @import("std");
const net = std.net;
const posix = std.posix;
const jwt = @import("jwt");
const configs = @import("../app/config.zig");
const clientFactory = @import("./client_factory.zig");

const Allocator = std.mem.Allocator;

pub const TCPClient = struct {
    host: []const u8,
    port: u16,
    secret: []const u8,

    pub fn init(host: []const u8, port: u16, secret: []const u8) TCPClient {
        return TCPClient{ .host = host, .port = port, .secret = secret };
    }

    pub fn create(allocator: Allocator, host: []const u8, port: u16, secret: []const u8) !clientFactory.Client {
        const tcp = try allocator.create(TCPClient);
        tcp.* = TCPClient.init(host, port, secret);
        return clientFactory.Client{
            .ptr = tcp,
            .destroyFn = destroy,
            .sendMessageFn = sendMessage,
        };
    }

    fn destroy(ptr: *anyopaque, allocator: Allocator) void {
        const self: *TCPClient = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }

    fn sendMessage(ptr: *anyopaque, message: *configs.LogConf, allocator: Allocator) !void {
        const self: *TCPClient = @ptrCast(@alignCast(ptr));

        //? one minute expiration added top of it
        message.*.exp = std.time.timestamp() + 60;

        const encoded = try jwt.encode(allocator, .{ .alg = .HS256 }, message.*, .{ .secret = self.secret });

        const address = try net.Address.parseIp(self.host, self.port);
        const tpe: u32 = posix.SOCK.STREAM;
        const protocol = posix.IPPROTO.TCP;
        const socket = try posix.socket(address.any.family, tpe, protocol);
        defer posix.close(socket);
        try posix.connect(socket, &address.any, address.getOsSockLen());
        _ = try posix.write(socket, encoded);

        defer allocator.free(encoded);
    }
};
