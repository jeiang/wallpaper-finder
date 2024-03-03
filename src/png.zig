const std = @import("std");
const fs = std.fs;

const utils = @import("utils.zig");
const Dimensions = utils.Dimensions(u32);

const logger = std.log.scoped(.png_parser);
const png_signature = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };
const expected_ihdr_marker = "IHDR";

pub const extensions = .{".png"};

pub const PngError = error{
    MissingIHDR,
} || utils.ImageError;

/// See https://stackoverflow.com/a/16725066
pub fn getSize(file: *fs.File) !Dimensions {
    var buf = [_]u8{0} ** (png_signature.len + @sizeOf(u32) + expected_ihdr_marker.len + @sizeOf(u32) * 2);
    const bytes_read = try file.readAll(&buf);
    if (bytes_read < buf.len) {
        return PngError.ReachedEof;
    }

    const signature = buf[0..png_signature.len];
    if (!std.mem.eql(u8, &png_signature, signature)) {
        logger.warn("file does not have a png signature, expected {X} got {X}", .{
            png_signature,
            signature,
        });
        return PngError.MissingSignature;
    }
    const ihdr_marker = buf[(png_signature.len + @sizeOf(u32))..(png_signature.len + @sizeOf(u32) + expected_ihdr_marker.len)];
    if (!std.mem.eql(u8, expected_ihdr_marker, ihdr_marker)) {
        logger.warn("png does not have IHDR at the expected position, expected {s} got {s}", .{
            expected_ihdr_marker,
            ihdr_marker,
        });
        return PngError.MissingIHDR;
    }

    const start_idx = @sizeOf(u32) + png_signature.len + expected_ihdr_marker.len;
    const height = std.mem.readInt(u32, buf[(start_idx + 4)..buf.len], .big);
    const width = std.mem.readInt(u32, buf[start_idx..(start_idx + 4)], .big);

    return Dimensions{
        .height = height,
        .width = width,
    };
}
