const std = @import("std");
const compress_service = @import("../engine/compressor.zig");

const enums = @import("../enum/config_enum.zig");

pub fn getCompressor(compression_type: enums.CompressType) type {
    switch (compression_type) {
        .gzip => {
            return compress_service.Gzip;
        },
    }
}
