const std = @import("std");
const datetime = @import("datetime").datetime;
const cron = @import("cron-time").Cron;
const Regex = @import("libregex").Regex;
const Allocator = std.mem.Allocator;

const configs = @import("../app/config.zig");

pub const CronService = struct {
    allocator: Allocator,
    confs: []configs.LogConf,
    tz: datetime.Timezone,

    pub fn init(allocator: Allocator, cfgs: []configs.LogConf, timezone: datetime.Timezone) !CronService {
        try validateCronExpression(cfgs);
        return .{
            .confs = cfgs,
            .tz = timezone,
            .allocator = allocator,
        };
    }

    pub fn start(self: CronService) void {
        sleepUntilNewMinute();
        while (true) {
            for (self.confs) |cfg| {
                std.log.scoped(.cron).debug("processing cron {s}: {s}", .{ cfg.app_name, cfg.cron_expression });
                const date = datetime.Datetime.now().shiftTimezone(&self.tz);
                var c = cron.init();
                c.parse(cfg.cron_expression) catch |err| {
                    std.log.scoped(.cron).err("error parsing cron {s}: {}", .{ cfg.cron_expression, err });
                    continue;
                };
                const next = c.next(date) catch |err| {
                    std.log.scoped(.cron).err("error calculating next run {}", .{err});
                    continue;
                };
                const duration = next.sub(date);

                if (duration.seconds < 59) {
                    std.log.scoped(.cron).info("Running logs processing for {s} with cron: {s}", .{ cfg.app_name, cfg.cron_expression });
                    std.debug.print("Running now\n", .{});
                    const files_to_process = findRegexMatchesInDir(self.allocator, cfg.logs_dir, cfg.log_files_regexp) catch |err| {
                        std.log.scoped(.cron).err("error getting files to process in {s}: {}", .{ cfg.logs_dir, err });
                        continue;
                    };
                    defer files_to_process.deinit();

                    for (files_to_process.items) |file| {
                        std.debug.print("{s}\n", .{file});
                    }
                } else {
                    std.debug.print("running in {d} seconds\n", .{duration.seconds});
                }
            }

            std.time.sleep(std.time.ns_per_min);
        }
    }

    fn validateCronExpression(confs: []configs.LogConf) !void {
        for (confs) |cfg| {
            var c = cron.init();
            try c.parse(cfg.cron_expression);
        }
    }

    fn sleepUntilNewMinute() void {
        const now = datetime.Datetime.now();
        const m: u64 = std.time.ns_per_s;
        const sleep_seconds = (59 - now.time.second);
        const sleep_nano_seconds = sleep_seconds * m;

        std.debug.print("Sleeping for {d} seconds\n", .{sleep_seconds});
        std.time.sleep(sleep_nano_seconds);
    }

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
};
