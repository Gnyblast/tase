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

pub const TruncateBy = enum {
    line,
    size,

    pub const TruncateByName = [@typeInfo(TruncateBy).@"enum".fields.len][:0]const u8{
        "lines",
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
