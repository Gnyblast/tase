const std = @import("std");
const net = std.net;
const posix = std.posix;
const jwt = @import("jwt");
const datetime = @import("datetime").datetime;

const configs = @import("../app/config.zig");
const AgentClaims = @import("../server/tcp.zig").AgentClaims;
const agentFactory = @import("../factory/agent_factory.zig");

const Allocator = std.mem.Allocator;

pub const TCPAgent = struct {
    host: []const u8,
    port: u16,
    secret: []const u8,

    pub fn init(host: []const u8, port: u16, secret: []const u8) TCPAgent {
        return TCPAgent{ .host = host, .port = port, .secret = secret };
    }

    pub fn create(allocator: Allocator, host: []const u8, port: u16, secret: []const u8) !agentFactory.Agent {
        const tcp = try allocator.create(TCPAgent);
        tcp.* = TCPAgent.init(host, port, secret);
        return agentFactory.Agent{
            .ptr = tcp,
            .destroyFn = destroy,
            .sendLogConfFn = sendLogConf,
        };
    }

    fn destroy(ptr: *anyopaque, allocator: Allocator) void {
        const self: *TCPAgent = @ptrCast(@alignCast(ptr));
        allocator.destroy(self);
    }

    //test-no-cover-start
    fn sendLogConf(ptr: *anyopaque, allocator: Allocator, cfg: configs.LogConf, timezone: datetime.Timezone) !void {
        const self: *TCPAgent = @ptrCast(@alignCast(ptr));

        const agentMsg = AgentClaims{
            .agent_hostname = "",
            .job = &cfg,
            .timezone = timezone,
            .exp = std.time.timestamp() + 60, //? one minute expiration added top of it
        };

        const encoded = try jwt.encode(allocator, .{ .alg = .HS256 }, agentMsg, .{ .secret = self.secret });
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
    //test-no-cover-end
};
