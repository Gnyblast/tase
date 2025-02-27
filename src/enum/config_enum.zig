pub const ActionStrategy = enum {
    truncate,
    rotate,
    delete,

    pub const ActionStrategyName = [@typeInfo(ActionStrategy).Enum.fields.len][:0]const u8{
        "truncate",
        "rotate",
        "delete",
    };

    pub fn str(self: ActionStrategy) [:0]const u8 {
        return ActionStrategyName[@intFromEnum(self)];
    }
};

pub const ActionFrom = enum {
    fromBottom,
    fromTop,

    pub const ActionFromName = [@typeInfo(ActionFrom).Enum.fields.len][:0]const u8{
        "bottom",
        "top",
    };

    pub fn str(self: ActionFrom) [:0]const u8 {
        return ActionFromName[@intFromEnum(self)];
    }
};

pub const ActionBy = enum {
    lines,
    megaBytes,

    pub const ActionByName = [@typeInfo(ActionBy).Enum.fields.len][:0]const u8{
        "lines",
        "megabytes",
    };

    pub fn str(self: ActionBy) [:0]const u8 {
        return ActionByName[@intFromEnum(self)];
    }
};
