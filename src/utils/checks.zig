const std = @import("std");
const configs = @import("../cli/config.zig");
const enums = @import("../enum/config_enum.zig");

pub fn doInitialChecks(cfgs: std.ArrayList(configs.LogConf)) !void {
    for (cfgs.items) |cfg| {
        var action_by_correct = false;
        for (enums.ActionBy.ActionByName) |action_by| {
            if (std.mem.eql(u8, cfg.action.by, action_by)) {
                action_by_correct = true;
                break;
            }
        }
        if (!action_by_correct) {
            return error.UnknownActionBy;
        }

        var action_from_correct = false;
        for (enums.ActionFrom.ActionFromName) |action_from| {
            if (std.mem.eql(u8, cfg.action.from, action_from)) {
                action_from_correct = true;
                break;
            }
        }
        if (!action_from_correct) {
            return error.UnknownActionFrom;
        }

        var action_type_correct = false;
        for (enums.ActionType.ActionTypeName) |action_type| {
            if (std.mem.eql(u8, cfg.action.type, action_type)) {
                action_type_correct = true;
                break;
            }
        }
        if (!action_type_correct) {
            return error.UnknownActionType;
        }
    }
}
