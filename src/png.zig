const std = @import("std");
const fs = std.fs;

const utils = @import("utils.zig");
const Dimensions = utils.Dimensions(u32);

const logger = std.log.scoped(.png_parser);
const png_signature = std.mem.readInt(u64, &[_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 }, .little);
const expected_ihdr_marker = std.mem.readInt(u32, "IHDR", .little);

pub const extensions = .{".png"};

pub const PngError = error{
    MissingIHDR,
} || utils.ImageError;

// should be 24 bytes
const PngStartingBytes = packed struct {
    signature: u64, // 8
    chunk_len: u32, // 4
    header: u32, // 4
    width: u32, // 4
    height: u32, // 4
};

/// See https://stackoverflow.com/a/16725066
pub fn getSize(file: *fs.File) !Dimensions {
    var buf = [_]u8{0} ** @sizeOf(PngStartingBytes);
    const bytes_read = try file.readAll(&buf);
    if (bytes_read < buf.len) {
        return PngError.ReachedEof;
    }

    const starting_bytes: PngStartingBytes = @bitCast(buf);

    if (starting_bytes.signature != png_signature) {
        logger.warn("file does not have a png signature, expected {X} got {X}", .{
            png_signature,
            starting_bytes.signature,
        });
        return PngError.MissingSignature;
    }
    if (starting_bytes.header != expected_ihdr_marker) {
        logger.warn("png does not have the IHDR chunk name at the expected position, expected {X} got {X}", .{
            expected_ihdr_marker,
            starting_bytes.header,
        });
        return PngError.MissingIHDR;
    }

    return Dimensions{
        .height = starting_bytes.height,
        .width = starting_bytes.width,
    };
}
