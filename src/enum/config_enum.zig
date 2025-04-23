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

pub const ActionFrom = enum {
    bottom,
    top,

    pub const ActionFromName = [@typeInfo(ActionFrom).@"enum".fields.len][:0]const u8{
        "bottom",
        "top",
    };

    pub fn str(self: ActionFrom) [:0]const u8 {
        return ActionFromName[@intFromEnum(self)];
    }
};

pub const ActionBy = enum {
    lines,
    megabytes,
    days,

    pub const ActionByName = [@typeInfo(ActionBy).@"enum".fields.len][:0]const u8{
        "lines",
        "megabytes",
        "days",
    };

    pub fn str(self: ActionBy) [:0]const u8 {
        return ActionByName[@intFromEnum(self)];
    }
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
