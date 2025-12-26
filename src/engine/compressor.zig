const std = @import("std");
const fs = std.fs;

const c = @cImport({
    @cInclude("zlib.h");
});

pub const Gzip = struct {
    pub fn compress(readFile: fs.File, writeFile: fs.File, level: u8) !void {
        var strm: c.z_stream = std.mem.zeroes(c.z_stream);
        // gzip = windowBits = 15 + 16
        if (c.deflateInit2_(
            &strm,
            c.Z_DEFAULT_COMPRESSION,
            c.Z_DEFLATED,
            15 + 16, // gzip
            level,
            c.Z_DEFAULT_STRATEGY,
            c.ZLIB_VERSION,
            @sizeOf(c.z_stream),
        ) != c.Z_OK)
            return error.DeflateInitFailed;

        defer _ = c.deflateEnd(&strm);

        var in_buf: [16 * 1024]u8 = undefined;
        var out_buf: [16 * 1024]u8 = undefined;

        while (true) {
            const read = try readFile.read(&in_buf);
            strm.next_in = if (read > 0) &in_buf else null;
            strm.avail_in = @intCast(read);

            const flush = if (read == 0) c.Z_FINISH else c.Z_NO_FLUSH;

            while (true) {
                strm.next_out = &out_buf;
                strm.avail_out = out_buf.len;

                const ret = c.deflate(&strm, flush);

                if (ret == c.Z_STREAM_ERROR)
                    return error.DeflateFailed;

                const have = out_buf.len - strm.avail_out;
                if (have > 0)
                    try writeFile.writeAll(out_buf[0..have]);

                if (strm.avail_out != 0)
                    break;
            }

            if (read == 0)
                break;
        }
    }
};
