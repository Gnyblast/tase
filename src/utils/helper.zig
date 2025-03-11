const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn toUpperCase(comptime string: []const u8) []u8 {
    var u_string: [string.len]u8 = std.mem.zeroes([string.len]u8);
    for (string, 0..) |s, i| {
        const u_s = std.ascii.toUpper(s);
        u_string[i] = u_s;
    }

    return &u_string;
}

pub fn concatString(allocator: Allocator, a: []const u8, b: []const u8) ![]const u8 {
    var new_str = try allocator.alloc(u8, a.len + b.len);
    std.mem.copyForwards(u8, new_str[0..], a);
    std.mem.copyForwards(u8, new_str[a.len..], b);
    return new_str;
}

pub fn arrayContains(comptime T: type, haystack: []const []const T, needle: []const T) bool {
    for (haystack) |item| {
        if (std.mem.eql(T, item, needle)) {
            return true;
        }
    }

    return false;
}

pub fn printApplicationInfo(run_type: []const u8, version: []const u8, host: []const u8, port: u16) void {
    const ascii =
        \\==================================
        \\████████╗ █████╗ ███████╗███████╗
        \\╚══██╔══╝██╔══██╗██╔════╝██╔════╝
        \\   ██║   ███████║███████╗█████╗  
        \\   ██║   ██╔══██║╚════██║██╔══╝  
        \\   ██║   ██║  ██║███████║███████╗
        \\   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝
        \\==================================
    ;

    std.log.info("\n{s}\nType: {s}\nVersion: v{s}\nListening at {s}:{d}", .{ ascii, run_type, version, host, port });
}
