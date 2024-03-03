const std = @import("std");
const config = @import("config.zig");

pub fn Dimensions(comptime T: type) type {
    return struct {
        height: T,
        width: T,

        const Self = @This();
        /// Returns gt iff one bound is greater than and the other is greater than or equal to
        pub fn cmp(self: *const Self, other: *const Self) std.math.Order {
            if (self.width == other.width and self.height == other.height) {
                return std.math.Order.eq;
            }
            if ((self.width <= other.width and self.height < other.height) or (self.width <= other.width and self.height < other.height)) {
                return std.math.Order.gt;
            }
            return std.math.Order.lt;
        }
    };
}
test "compare gt" {
    const a = Dimensions(u32){
        .height = 10,
        .width = 10,
    };
    const b = Dimensions(u32){
        .height = 15,
        .width = 15,
    };
    try std.testing.expectEqual(std.math.Order.gt, a.cmp(&b));
}
test "compare lt" {
    const a = Dimensions(u32){
        .height = 10,
        .width = 10,
    };
    const b = Dimensions(u32){
        .height = 5,
        .width = 5,
    };
    try std.testing.expectEqual(std.math.Order.lt, a.cmp(&b));
}
test "compare eq" {
    const a = Dimensions(u32){
        .height = 10,
        .width = 10,
    };
    const b = Dimensions(u32){
        .height = 10,
        .width = 10,
    };
    try std.testing.expectEqual(std.math.Order.eq, a.cmp(&b));
}
test "compare semi-lt semi-gt" {
    const a = Dimensions(u32){
        .height = 10,
        .width = 10,
    };
    const b = Dimensions(u32){
        .height = 15,
        .width = 5,
    };
    try std.testing.expectEqual(std.math.Order.lt, a.cmp(&b));
}
test "compare semi-lt semi-gt 2" {
    const a = Dimensions(f64){
        .height = 1500,
        .width = 1300,
    };
    const b = Dimensions(f64){
        .height = 1500 * 0.9,
        .width = 1300 * 0.9,
    };
    try std.testing.expectEqual(std.math.Order.lt, a.cmp(&b));
}

pub const ImageError = error{
    MissingSignature,
    ReachedEof,
};

// get cwd fd
const cwd = std.fs.cwd();

pub fn openDir(path: []const u8) std.fs.File.OpenError!std.fs.Dir {
    return cwd.openDir(path, .{ .iterate = true });
}
