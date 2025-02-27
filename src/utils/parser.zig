const std = @import("std");
const argsParser = @import("args");

const configs = @import("../cli/config.zig");

const Allocator = std.mem.Allocator;

pub fn parseCLI(alloc: Allocator) !argsParser.ParseArgsResult(configs.argOpts, null) {
    return try argsParser.parseForCurrentProcess(configs.argOpts, alloc, .print);
    //TODO: print args
}
