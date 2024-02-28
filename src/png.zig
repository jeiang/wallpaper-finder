const common = @import("common.zig");
const std = @import("std");
const fs = std.fs;

const expected_signature = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };
const expected_ihdr_marker = "IHDR";

/// See https://stackoverflow.com/a/16725066
pub fn checkPngSize(file: *fs.File) !?common.Dimensions {
    var buf = [_]u8{0} ** (expected_signature.len + @sizeOf(u32) + expected_ihdr_marker.len + @sizeOf(u32) * 2);
    const bytes_read = try file.readAll(&buf);
    if (bytes_read < buf.len) {
        return null;
    }

    const signature = buf[0..expected_signature.len];
    if (!std.mem.eql(u8, &expected_signature, signature)) {
        return null;
    }
    const ihdr_marker = buf[(expected_signature.len + @sizeOf(u32))..(expected_signature.len + @sizeOf(u32) + expected_ihdr_marker.len)];
    if (!std.mem.eql(u8, expected_ihdr_marker, ihdr_marker)) {
        return null;
    }

    const start_idx = @sizeOf(u32) + expected_signature.len + expected_ihdr_marker.len;
    const height = std.mem.readInt(u32, buf[(start_idx + 4)..buf.len], .big);
    const width = std.mem.readInt(u32, buf[start_idx..(start_idx + 4)], .big);

    return common.Dimensions{
        .height = height,
        .width = width,
    };
}
