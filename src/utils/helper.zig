const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub fn toUpperCase(allocator: Allocator, string: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, string.len);
    for (string, 0..) |s, i| {
        result[i] = std.ascii.toUpper(s);
    }
    return result;
}

pub fn toLowerCase(allocator: Allocator, input: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, input.len);
    for (input, 0..) |ch, i| {
        result[i] = std.ascii.toLower(ch);
    }
    return result;
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

pub fn bytesToMegabytes(bytes: u64) f64 {
    const bytes_f: f64 = @floatFromInt(bytes);
    return bytes_f / 1_048_576.0;
}

pub fn dupeOptString(allocator: Allocator, value: ?[]const u8) !?[]const u8 {
    return if (value) |v| try allocator.dupe(u8, v) else null;
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

test "toUpperCaseTest" {
    const s: []const u8 = "aaaaaa";
    const expected: []const u8 = "AAAAAA";

    var allocator = testing.allocator;
    const actual = try toUpperCase(allocator, s);
    defer allocator.free(actual);
    try testing.expectEqualDeep(expected, actual);
}

test "toLowerCaseTest" {
    const s: []const u8 = "AAAAAA";
    const expected: []const u8 = "aaaaaa";

    var allocator = testing.allocator;
    const actual = try toLowerCase(allocator, s);
    defer allocator.free(actual);
    try testing.expectEqualDeep(expected, actual);
}

test "concatStringtest" {
    const a: []const u8 = "AAAAAA";
    const b: []const u8 = "aaaaaa";
    const expected: []const u8 = "AAAAAAaaaaaa";

    var allocator = testing.allocator;
    const actual = try concatString(allocator, a, b);
    defer allocator.free(actual);
    try testing.expectEqualDeep(expected, actual);
}

test "arrayContainsTest" {
    var haystack: [3][]const u8 = .{ "test", "test1", "test2" };
    const needle = "test1";

    const expected = true;
    const actual = arrayContains(u8, &haystack, needle);
    try testing.expectEqual(expected, actual);
}

test "bytesToMegabytesTest" {
    const actual = bytesToMegabytes(71263712);
    try testing.expectEqual(6.796237182617188e1, actual);
}
