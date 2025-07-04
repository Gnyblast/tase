const std = @import("std");
const helper = @import("prune_helper.zig");
const enums = @import("../enum/config_enum.zig");
const TaseNativeErrors = @import("../factory/error_factory.zig").TaseNativeErrors;
const Pruner = @import("./pruner.zig").Pruner;

const Allocator = std.mem.Allocator;

pub fn doTruncate(pruner: Pruner) !void {
    switch (std.meta.stringToEnum(enums.TruncateFrom, pruner.log_action.truncate_settings.?.from.?) orelse return TaseNativeErrors.InvalidTruncateFromFieldValue) {
        .bottom => {
            try processForBottom(pruner);
        },
        .top => {
            try processForTop(pruner);
        },
    }
}

fn processForBottom(pruner: Pruner) !void {
    switch (std.meta.stringToEnum(enums.TruncateAction, pruner.log_action.truncate_settings.?.action.?) orelse return TaseNativeErrors.InvalidTruncateActionFieldValue) {
        .keep => try processKeepBottom(pruner),
        .delete => try processDeleteBottom(pruner),
    }
}

fn processKeepBottom(pruner: Pruner) !void {
    switch (std.meta.stringToEnum(enums.TruncateBy, pruner.log_action.truncate_settings.?.by.?) orelse return TaseNativeErrors.InvalidTruncateByFieldValue) {
        .size => try keepBottomBySize(pruner),
        .line => try keepBottomByLine(pruner),
    }
}

fn processDeleteBottom(pruner: Pruner) !void {
    switch (std.meta.stringToEnum(enums.TruncateBy, pruner.log_action.truncate_settings.?.by.?) orelse return TaseNativeErrors.InvalidTruncateByFieldValue) {
        .size => try deleteBottomBySize(pruner),
        .line => try deleteBottomByLine(pruner),
    }
}

fn keepBottomBySize(_: Pruner) !void {}
fn keepBottomByLine(_: Pruner) !void {}
fn deleteBottomBySize(_: Pruner) !void {}
fn deleteBottomByLine(_: Pruner) !void {}

fn processForTop(pruner: Pruner) !void {
    switch (std.meta.stringToEnum(enums.TruncateAction, pruner.log_action.truncate_settings.?.action.?) orelse return TaseNativeErrors.InvalidTruncateActionFieldValue) {
        .keep => try processKeepTop(pruner),
        .delete => try processDeleteTop(pruner),
    }
}

fn processKeepTop(pruner: Pruner) !void {
    switch (std.meta.stringToEnum(enums.TruncateBy, pruner.log_action.truncate_settings.?.by.?) orelse return TaseNativeErrors.InvalidTruncateByFieldValue) {
        .size => try keepTopBySize(pruner),
        .line => try keepTopByLine(pruner),
    }
}

fn processDeleteTop(pruner: Pruner) !void {
    switch (std.meta.stringToEnum(enums.TruncateBy, pruner.log_action.truncate_settings.?.by.?) orelse return TaseNativeErrors.InvalidTruncateByFieldValue) {
        .size => try deleteTopBySize(pruner),
        .line => try deleteTopByLine(pruner),
    }
}

fn keepTopBySize(_: Pruner) !void {}
fn keepTopByLine(_: Pruner) !void {}
fn deleteTopBySize(_: Pruner) !void {}
fn deleteTopByLine(_: Pruner) !void {}
