const common = @import("common.zig");
const std = @import("std");
const fs = std.fs;

const jpg_signature = [_]u8{ 0xFF, 0xD8, 0xFF, 0xE0 };

fn readu16be(file: *fs.File) ?u16 {
    var u16_buf = [2]u8{ 0, 0 }; // u16be
    const bytes_read = file.readAll(&u16_buf) catch return null;
    if (bytes_read < u16_buf.len) {
        return null;
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

/// See https://stackoverflow.com/a/63479164 and https://web.archive.org/web/20131016210645/http://www.64lines.com/jpeg-width-height
pub fn checkJpgSize(file: *fs.File) !?common.Dimensions {
    var signature = [_]u8{0} ** jpg_signature.len;
    const bytes_read = try file.readAll(&signature);
    if (bytes_read < signature.len or !std.mem.eql(u8, &jpg_signature, &signature)) {
        return null;
    }

    // Retrieve the block length of the first block since the first block will
    // not contain the size of file
    var block_size = readu16be(file) orelse return null;
    block_size -= 2; // account for reading of block
    while (true) {
        file.seekBy(block_size) catch return null;
        const marker = readu16be(file) orelse return null;

        if (!isFrameMarker(marker)) {
            return null;
        }

        if (!isSOFMarker(marker)) {
            // goto next block
            block_size = readu16be(file) orelse return null;
            block_size -= 2; // account for reading of block
            continue;
        }

        // if here, found a SOF frame
        // skip next 4 bytes due to structure of frame
        // [0xFFC0][u16 length][u8 precision][u16 x][u16 y]
        file.seekBy(@sizeOf(u16) + @sizeOf(u8)) catch return null;
        const height = readu16be(file) orelse return null;
        const width = readu16be(file) orelse return null;

        return .{
            .height = height,
            .width = width,
        };
    }

    return null;
}
