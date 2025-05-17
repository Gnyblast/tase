const std = @import("std");
const testing = std.testing;

pub const ActionStrategy = enum {
    truncate,
    rotate,
    delete,

    pub const ActionStrategyName = [@typeInfo(ActionStrategy).@"enum".fields.len][:0]const u8{
        "truncate",
        "rotate",
        "delete",
    };

    pub fn str(self: ActionStrategy) [:0]const u8 {
        return ActionStrategyName[@intFromEnum(self)];
    }
};

pub const TruncateAction = enum {
    keep,
    delete,

    pub const TruncateActionName = [@typeInfo(TruncateAction).@"enum".fields.len][:0]const u8{
        "keep",
        "delete",
    };

    pub fn str(self: TruncateAction) [:0]const u8 {
        return TruncateActionName[@intFromEnum(self)];
    }
};

pub const TruncateBy = enum {
    line,
    size,

    pub const TruncateByName = [@typeInfo(TruncateBy).@"enum".fields.len][:0]const u8{
        "line",
        "size",
    };

    pub fn str(self: TruncateBy) [:0]const u8 {
        return TruncateByName[@intFromEnum(self)];
    }
};

pub const TruncateFrom = enum {
    bottom,
    top,

    pub const TruncateFromName = [@typeInfo(TruncateFrom).@"enum".fields.len][:0]const u8{
        "bottom",
        "top",
    };

    pub fn str(self: TruncateFrom) [:0]const u8 {
        return TruncateFromName[@intFromEnum(self)];
    }
};

pub const IfConditions = enum {
    size,
    days,

    pub const IfConditionName = [@typeInfo(IfConditions).@"enum".fields.len][:0]const u8{
        "size",
        "days",
    };

    pub fn str(self: IfConditions) [:0]const u8 {
        return IfConditionName[@intFromEnum(self)];
    }
};

pub const Operators = enum {
    @">",
    @"<",
    @"=",
};

pub const CompressType = enum {
    gzip,

    pub const CompressTypeName = [@typeInfo(CompressType).@"enum".fields.len][:0]const u8{
        "gzip",
    };

    pub fn str(self: CompressType) [:0]const u8 {
        return CompressTypeName[@intFromEnum(self)];
    }

    pub fn getCompressionExtension(self: CompressType) []const u8 {
        switch (self) {
            .gzip => {
                return "gz";
            },
        }
    }
};

test "ActionStrategyTest" {
    try testing.expectEqualDeep("truncate", ActionStrategy.truncate.str());
    try testing.expectEqualDeep("delete", ActionStrategy.delete.str());
    try testing.expectEqualDeep("rotate", ActionStrategy.rotate.str());
}

test "TruncateByTest" {
    try testing.expectEqualDeep("line", TruncateBy.line.str());
    try testing.expectEqualDeep("size", TruncateBy.size.str());
}

test "TruncateFromTest" {
    try testing.expectEqualDeep("bottom", TruncateFrom.bottom.str());
    try testing.expectEqualDeep("top", TruncateFrom.top.str());
}

test "TruncateActionTest" {
    try testing.expectEqualDeep("delete", TruncateAction.delete.str());
    try testing.expectEqualDeep("keep", TruncateAction.keep.str());
}

test "IfConditionsTest" {
    try testing.expectEqualDeep("size", IfConditions.size.str());
    try testing.expectEqualDeep("days", IfConditions.days.str());
}

test "CompressTypeTest" {
    try testing.expectEqualDeep("gzip", CompressType.gzip.str());
    try testing.expectEqualDeep("gz", CompressType.gzip.getCompressionExtension());
}
