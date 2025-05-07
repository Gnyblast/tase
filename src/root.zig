const std = @import("std");
const varint = @import("main.zig");

test {
    std.testing.refAllDecls(varint);
}
