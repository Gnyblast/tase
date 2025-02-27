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
