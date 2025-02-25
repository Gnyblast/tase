const std = @import("std");

pub fn toUpperCase(comptime string: []const u8) []u8 {
    var u_string: [string.len]u8 = std.mem.zeroes([string.len]u8);
    for (string, 0..) |s, i| {
        const u_s = std.ascii.toUpper(s);
        u_string[i] = u_s;
    }

    return &u_string;
}
