const std = @import("std");

const enums = @import("../enum/config_enum.zig");

pub fn getCompressor(compression_type: enums.CompressType) type {
    switch (compression_type) {
        .gzip => {
            return std.compress.gzip;
        },
    }
}
