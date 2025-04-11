const std = @import("std");
const Regex = @import("libregex").Regex;
const Allocator = std.mem.Allocator;

/// const files_to_process = findRegexMatchesInDir(self.allocator, cfg.logs_dir, cfg.log_files_regexp) catch |err| {
///         std.log.scoped(.cron).err("error getting files to process in {s}: {}", .{ cfg.logs_dir, err });
///         continue;
///     };
/// defer files_to_process.deinit();
fn findRegexMatchesInDir(allocator: Allocator, dir: []const u8, regexp: []const u8) !std.ArrayList([]const u8) {
    var files = try std.fs.openDirAbsolute(dir, .{ .iterate = true, .access_sub_paths = false });
    defer files.close();

    var matchedFiles = std.ArrayList([]const u8).init(allocator);

    var f_it = files.iterate();
    while (try f_it.next()) |file| {
        const regex = try Regex.init(allocator, regexp, "x");
        defer regex.deinit();

        const matched = regex.matches(file.name) catch |err| {
            std.log.scoped(.cron).err("error matching file {s}: {}", .{ file.name, err });
            continue;
        };

        if (matched) {
            try matchedFiles.append(file.name);
        }
    }

    return matchedFiles;
}
