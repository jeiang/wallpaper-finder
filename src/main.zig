const std = @import("std");
const common = @import("common.zig");
const png = @import("png.zig");
const jpg = @import("jpg.zig");

// TODO: proper command line args
// TODO: command line ratio specification with configurable "closeness range???" (i.e. +- 5%)
// TODO: find a better method of allocation
// TODO: multithread?? idk no async so not optimal

fn run(path: []const u8) !void {
    const stdout_writer = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_writer);
    const stdout = bw.writer();

    const root = try std.fs.openDirAbsolute(path, .{ .iterate = true });
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var walker = try root.walk(alloc);
    while (try walker.next()) |entry| {
        const basename = entry.basename;
        if (entry.path.len < 4 or entry.kind != .file) {
            continue; // idk how reach here but whatever
        }
        const len = entry.basename.len;
        var dim: ?common.Dimensions = undefined;
        if (std.mem.eql(u8, basename[len - 3 .. len], "jpg") or std.mem.eql(u8, basename[len - 4 .. len], "jpeg")) {
            var file = try root.openFile(entry.path, .{});
            dim = try jpg.checkJpgSize(&file);
        } else if (std.mem.eql(u8, basename[len - 3 .. len], "png")) {
            var file = try root.openFile(entry.path, .{});
            dim = try png.checkPngSize(&file);
        } else {
            continue;
        }
        if (dim) |dimension| {
            const ratio = @as(f64, @floatFromInt(dimension.width)) / @as(f64, @floatFromInt(dimension.height));
            if (1.7 < ratio and ratio < 1.8) {
                try stdout.print("{s}{s}\n", .{
                    path,
                    entry.path,
                });
                try bw.flush();
            }
        }
    }
}

var args_buffer = [_]u8{0} ** (1024);

pub fn main() !void {
    var fba = std.heap.FixedBufferAllocator.init(&args_buffer);
    const alloc = fba.allocator();
    var args = try std.process.ArgIterator.initWithAllocator(alloc);
    // skip exe
    _ = args.skip();
    // grab path
    if (args.next()) |path| {
        try run(path);
        return;
    }

    const stderr_writer = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr_writer);
    const stderr = bw.writer();
    try stderr.print("usage: <exe> <path>\n", .{});
    try bw.flush();
    return;
}
