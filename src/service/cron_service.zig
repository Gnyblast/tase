const std = @import("std");
const datetime = @import("datetime").datetime;
const cron = @import("cron-time").Cron;

const configs = @import("../app/config.zig");

pub const CronService = struct {
    confs: []configs.LogConf,
    tz: datetime.Timezone,

    pub fn init(cfgs: []configs.LogConf, timezone: datetime.Timezone) !CronService {
        try validateCronExpression(cfgs);
        return .{
            .confs = cfgs,
            .tz = timezone,
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
};
