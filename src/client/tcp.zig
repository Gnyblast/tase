const std = @import("std");
const net = std.net;
const posix = std.posix;
const jwt = @import("jwt");
const datetime = @import("datetime").datetime;

const configs = @import("../app/config.zig");
const AgentClaims = @import("../server/tcp.zig").AgentClaims;
const clientFactory = @import("../factory/client_factory.zig");

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
            .sendLogConfFn = sendLogConf,
        };
    }

    fn destroy(ptr: *anyopaque, allocator: Allocator) void {
        const self: *TCPClient = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }

    fn sendLogConf(ptr: *anyopaque, allocator: Allocator, cfg: configs.LogConf, timezone: datetime.Timezone) !void {
        const self: *TCPClient = @ptrCast(@alignCast(ptr));

        const clientMsg = AgentClaims{
            .agent_hostname = "",
            .job = &cfg,
            .timezone = timezone,
            .exp = std.time.timestamp() + 60, //? one minute expiration added top of it
        };

        const encoded = try jwt.encode(allocator, .{ .alg = .HS256 }, clientMsg, .{ .secret = self.secret });
        defer allocator.free(encoded);

        const address = try net.getAddressList(allocator, self.host, self.port);
        defer address.deinit();
        const tpe: u32 = posix.SOCK.STREAM;
        const protocol = posix.IPPROTO.TCP;
        const socket = try posix.socket(address.addrs[0].any.family, tpe, protocol);
        defer posix.close(socket);
        try posix.connect(socket, &address.addrs[0].any, address.addrs[0].getOsSockLen());

        //TODO check success
        _ = try posix.write(socket, encoded);
    }
};
