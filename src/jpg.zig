const std = @import("std");
const fs = std.fs;
const utils = @import("utils.zig");
const Dimensions = utils.Dimensions(u32);

const logger = std.log.scoped(.jpg_parser);
const jpg_signature = [_]u8{ 0xFF, 0xD8, 0xFF, 0xE0 };
const jfif_signature = [_]u8{ 0xFF, 0xD8, 0xFF, 0xE1 };

pub const extensions = .{
    ".jpg",
    ".jpeg",
    ".jfif",
};

pub const JpgError = error{
    NoFrameMarker,
    NoStartOfFrameFound,
} || utils.ImageError;

/// See https://stackoverflow.com/a/63479164 and https://web.archive.org/web/20131016210645/http://www.64lines.com/jpeg-width-height
pub fn getSize(file: *fs.File) !Dimensions {
    var signature_buf = [_]u8{0} ** jpg_signature.len;
    const bytes_read = try file.readAll(&signature_buf);
    const signature = signature_buf[0..bytes_read];
    if (!std.mem.eql(u8, &jpg_signature, signature) and !std.mem.eql(u8, &jfif_signature, signature)) {
        logger.warn("file does not have a jpg signature: expected either {X} or {X}, got {X}", .{
            jpg_signature,
            jfif_signature,
            signature,
        });
        return JpgError.MissingSignature;
    }

    // Retrieve the block length of the first block since the first block will
    // not contain the size of file
    var block_size = try readu16be(file);
    block_size -= 2; // account for reading of block
    while (true) {
        file.seekBy(block_size) catch |err| {
            logger.err("failed to seek in file due to {!}", .{err});
            return err;
        };
        const marker = try readu16be(file);

        if (!isFrameMarker(marker)) {
            logger.warn("while searching for the SOF marker, jumped to an invalid frame marker, expected {X} got {X}", .{
                0xFF,
                marker,
            });
            return JpgError.NoFrameMarker;
        }

        if (!isSOFMarker(marker)) {
            // goto next block
            block_size = try readu16be(file);
            block_size -= 2; // account for reading of block
            logger.debug("found {X} marker, skipping ahead {X} bytes to next frame", .{ marker, block_size });
            continue;
        }

        // if here, found a SOF frame
        // skip next 4 bytes due to structure of frame
        // [0xFFC0][u16 length][u8 precision][u16 x][u16 y]
        file.seekBy(@sizeOf(u16) + @sizeOf(u8)) catch |err| {
            logger.err("failed to seek in file due to {!}", .{err});
            return err;
        };
        const height = try readu16be(file);
        const width = try readu16be(file);

        return .{
            .height = height,
            .width = width,
        };
    }

    return JpgError.NoStartOfFrameFound;
}

fn readu16be(file: *fs.File) !u16 {
    var u16_buf = [2]u8{ 0, 0 }; // u16be
    const bytes_read = try file.readAll(&u16_buf);
    if (bytes_read < u16_buf.len) {
        return JpgError.ReachedEof;
    }
    return std.mem.readInt(u16, &u16_buf, .big);
}

fn isFrameMarker(marker: u16) bool {
    return (marker & 0xFF00) == 0xFF00;
}

// match against SOFn frame as described in https://stackoverflow.com/a/63479164
fn isSOFMarker(marker: u16) bool {
    // check first byte is FF and second is Cn
    return (marker & 0xFFF0) == 0xFFC0;
}
